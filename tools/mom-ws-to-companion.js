const WebSocket = require('ws')
const http = require('http')

const WS_URL = process.env.WS_URL || 'ws://127.0.0.1:8080/mom/subscribe'
const COMPANION = process.env.COMPANION || '127.0.0.1:8000' // change if your Companion runs elsewhere

function setVar(name, value) {
  const path = `/api/custom-variable/${encodeURIComponent(name)}/value?value=${encodeURIComponent(String(value))}`
  const [host, port] = COMPANION.split(':')
  const opts = { host, port: Number(port || 80), path, method: 'POST' }
  const req = http.request(opts, (res) => res.resume())
  req.on('error', () => {})
  req.end()
}

const ws = new WebSocket(WS_URL)
ws.on('open', () => console.log('WS connected:', WS_URL))
ws.on('message', (data) => {
  try {
    const s = JSON.parse(data)
    setVar('Mom_ActiveLayer', s.layer ?? '')
    setVar('Mom_CUT', s.cut ? 1 : 0)
    setVar('Mom_DIM', s.dim ? 1 : 0)
    // example for a specific LED (Layer 1, Key 1):
    const led = (s.keyLed && s.keyLed['1:1']) ? 1 : 0
    setVar('Mom_Key_1_LED', led)
  } catch (e) {}
})
ws.on('close', () => process.exit(0))
