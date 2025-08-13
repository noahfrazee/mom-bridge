import Vapor
import Foundation
import Surrogate // PADL C API

struct MomKeyReq: Content { let layer: Int; let key: Int; let pressed: Bool }
struct MomEncReq: Content { let delta: Int }
struct MomLayerReq: Content { let layer: Int }

struct MomState: Content {
    var connected: Bool
    var layer: Int
    var keyLed: [String: Bool]
    var cut: Bool
    var dim: Bool
    var levelDb: Double?
}

final class MomBridge {
    private(set) var state = MomState(connected: false, layer: 1, keyLed: [:], cut: false, dim: false, levelDb: nil)
    private var subscribers = [WebSocket]()

    private var ctrl: MOMControllerRef?
    private var heartbeat: DispatchSourceTimer?

    private let MOM_STATUS_SUCCESS: CFIndex = 0
    private let MOM_KEY_TALK: Int32 = 9
    private let MOM_EVENT_SET_KEY_STATE = MOMEvent(rawValue: 23)! // unwrap once

    private let talkLayer = 1
    private let talkKey   = 5

    func connect() {
        print("[MOM] connect() starting")
        if ctrl != nil {
            state.connected = true
            pushState()
            return
        }

        guard let controller = MOMControllerCreate(
            kCFAllocatorDefault,
            nil,
            nil,
            { _, _, _, _, _ in
                return MOMStatus(rawValue: 0)! // success
            }
        ) else {
            print("[MOM] Controller create failed"); return
        }
        self.ctrl = controller

        let st = MOMControllerBeginDiscoverability(controller)
        print("[MOM] BeginDiscoverability ->", st.rawValue)
        guard st.rawValue == MOM_STATUS_SUCCESS else { return }

        let ann = MOMControllerAnnounceDiscoverability(controller)
        print("[MOM] AnnounceDiscoverability (initial) ->", ann.rawValue)

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let c = self.ctrl else { return }
            _ = MOMControllerSendDeferred(c)
            struct Counter { static var i = 0 }
            Counter.i &+= 1
            if Counter.i % 3 == 0 {
                let r = MOMControllerAnnounceDiscoverability(c)
                if r.rawValue != self.MOM_STATUS_SUCCESS {
                    print("[MOM] Re-announce failed ->", r.rawValue)
                }
            }
        }
        timer.resume()
        self.heartbeat = timer

        state.connected = true
        pushState()
    }

    func key(layer: Int, key: Int, pressed: Bool) {
        guard let c = ctrl else {
            state.keyLed["\(layer):\(key)"] = pressed
            pushState()
            return
        }

        if layer == talkLayer && key == talkKey {
            var keyNum: Int32 = MOM_KEY_TALK
            var keyState: Int32 = pressed ? 1 : 0

            let nKey   = CFNumberCreate(nil, .sInt32Type, &keyNum)!
            let nState = CFNumberCreate(nil, .sInt32Type, &keyState)!

            var callbacks = kCFTypeArrayCallBacks
            let params = CFArrayCreateMutable(nil, 0, &callbacks)
            CFArrayAppendValue(params, Unmanaged.passUnretained(nKey).toOpaque())
            CFArrayAppendValue(params, Unmanaged.passUnretained(nState).toOpaque())

            let st = MOMControllerNotify(c, MOM_EVENT_SET_KEY_STATE, params)
            if st.rawValue == MOM_STATUS_SUCCESS {
                state.keyLed["\(layer):\(key)"] = pressed
                pushState()
            } else {
                print("[MOM] SetKeyState notify failed ->", st.rawValue)
            }
            return
        }

        state.keyLed["\(layer):\(key)"] = pressed
        pushState()
    }

    func encoder(delta: Int) {
        state.levelDb = (state.levelDb ?? 0) + Double(delta)
        pushState()
    }

    func setLayer(_ layer: Int) {
        state.layer = layer
        pushState()
    }

    func addWS(_ ws: WebSocket) {
        subscribers.append(ws)
        ws.onClose.whenComplete { [weak self] _ in
            self?.subscribers.removeAll { $0.isClosed }
        }
        sendState(to: ws)
    }
    private func pushState() { subscribers.forEach { sendState(to: $0) } }
    private func sendState(to ws: WebSocket) {
        if let data = try? JSONEncoder().encode(state),
           let json = String(data: data, encoding: .utf8) { ws.send(json) }
    }
}

let bridge = MomBridge()

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    app.post("mom","connect") { _ -> HTTPStatus in
        print("[HTTP] /mom/connect hit")
        bridge.connect()
        return .ok
    }

    app.post("mom","key") { req -> HTTPStatus in
        let b = try req.content.decode(MomKeyReq.self)
        bridge.key(layer: b.layer, key: b.key, pressed: b.pressed); return .ok
    }

    app.post("mom","encoder") { req -> HTTPStatus in
        let b = try req.content.decode(MomEncReq.self)
        bridge.encoder(delta: b.delta); return .ok
    }

    app.post("mom","layer") { req -> HTTPStatus in
        let b = try req.content.decode(MomLayerReq.self)
        bridge.setLayer(b.layer); return .ok
    }

    app.get("mom","state") { _ -> MomState in bridge.state }
    app.webSocket("mom","subscribe") { _, ws in bridge.addWS(ws) }
}

@main
struct Main {
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }
        try routes(app)
        try app.run()
    }
}