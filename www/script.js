// TODO: (dynamic) scaling
const scale = 2;

const canvas = /** @type {HTMLCanvasElement} */(document.getElementById('display'));
const ctx = canvas.getContext('2d');

function publicLog(message) {
  var messageLog = document.getElementById("message-log");

  var messagePara = document.createElement("p");
  messagePara.textContent = message;

  messageLog.appendChild(messagePara);
}

// idx | msg
// ----|-------------
//  0  | Input
//  1  | GetUpdate
//  2  | PowerButton
const getUpdateMsg = new ArrayBuffer(5); // 4 byte index, 1 byte GetUpdate
const updateView = new DataView(getUpdateMsg);
updateView.setInt32(0, 1, /* little */ true);

const inputMsg = new ArrayBuffer(20); // idx | x: 4, y: 4, action 4, touch: 1 bytes + padding
const inputView = new DataView(inputMsg);
inputView.setInt32(0, 0, true); // set index.

function sendInput(type, event) {
  inputView.setInt32(4, event.offsetX * scale, /* little */ true);
  inputView.setInt32(8, event.offsetY * scale, /* little */ true);

  // 0 = move, 1 = down, 2 = up.
  let action = 0;
  if (type == 'down') {
    action = 1;
  } else if (type == 'up') {
    action = 2;
  }
  inputView.setInt32(12, action, /* little */ true);
  // 0 = pen, 1 = touch.
  inputView.setInt32(16, 0, /* little */ true);
  ws.send(inputMsg);
  console.log("Sent input!");
}

canvas.addEventListener('mousedown', (event) => { sendInput('down', event); });
canvas.addEventListener('mouseup', (event) => { sendInput('up', event); });
canvas.addEventListener('mousemove', (event) => { sendInput('move', event); });


// Create a new WebSocket object
var ws = new WebSocket(`ws://${window.location.host}/socket`);
ws.binaryType = "arraybuffer";

// Handle the connection open event
ws.onopen = function() {
  publicLog("WebSocket connection opened!");
  // Send get screen packet
  ws.send(getUpdateMsg);
};


/**
 * @param {DataView} view
 */
function showUpdate(view) {
  console.log("Showing update!");

  const image = ctx.createImageData(currentUpdate.width, currentUpdate.height);

  let idx = 0;
  for (let i = 0; i < view.byteLength; i += 2) {
    let rgb = view.getInt16(i, /* little */ true);

    let b = (rgb & 0x1f) << 3;
    let g = ((rgb >> 5) & 0x3f) << 2;
    let r = ((rgb >> 11) & 0x1f) << 3;

    image.data[idx++] = r;
    image.data[idx++] = g;
    image.data[idx++] = b;
    image.data[idx++] = 255;
  }

  const pos = {dx: currentUpdate.x1 / scale, dy: currentUpdate.y1 / scale};
  window.createImageBitmap(
    image,
    0,
    0,
    image.width,
    image.height,
    { resizeWidth: image.width / scale, resizeHeight: image.height / scale }
  ).then((bitmap) => {
    ctx.drawImage(bitmap, pos.dx, pos.dy);
    console.log("Updated image!");
  });
}

const msgSize = 6 * 4;
const maxScreenUpdate = 1872 * 1404 * 2;
const buffer = new Uint8Array(msgSize + maxScreenUpdate);
var bufferOffset = 0;

var currentUpdate = null;

function consumeFront(size) {
  buffer.copyWithin(0, size, bufferOffset);
  bufferOffset -= size;
}

function getNextExpectedSize() {
  if (currentUpdate == null) {
    return msgSize;
  }

  return currentUpdate.width * currentUpdate.height * 2;
}

function processData() {
  while (bufferOffset >= getNextExpectedSize()) {
    if (currentUpdate == null) {
      const view = new DataView(buffer.buffer, 0, msgSize);
      const msg = {
        // int y1;
        y1: view.getInt32(0, /* little */ true),
        // int x1;
        x1: view.getInt32(4, /* little */ true),
        // int y2;
        y2: view.getInt32(8, /* little */ true),
        // int x2;
        x2: view.getInt32(12, /* little */ true),

        // int flags;
        flags: view.getInt32(16, /* little */ true),
        // int waveform;
        wave: view.getInt32(20, /* little */ true),
      };

      msg.width = msg.x2 - msg.x1 + 1;
      msg.height = msg.y2 - msg.y1 + 1;

      currentUpdate = msg;
      console.log("Got message:", msg);
      consumeFront(msgSize);
    } else {
      const size = getNextExpectedSize();
      showUpdate(new DataView(buffer.buffer, 0, size));
      consumeFront(size);
      currentUpdate = null;
    }
  }
}

// Handle incoming messages
ws.onmessage = function(event) {
  if (event.data instanceof ArrayBuffer) {
    const data = new Uint8Array(event.data);

    // Append data to buffer, assert (for now) if not possible.
    console.assert(data.byteLength + bufferOffset <= buffer.byteLength);
    buffer.set(data, bufferOffset);
    bufferOffset += data.byteLength;

    // Process all available data
    processData();

  } else {
    console.log("Received message:", event.data);
  }
};

// Handle any errors that might occur
ws.onerror = function(error) {
  console.error("WebSocket error:", error);
};

ws.onclose = function(event) {
  console.error("Websocket closed:", event.reason);
}
