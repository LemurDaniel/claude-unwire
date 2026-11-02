// Devices view: lists the connected devices and blocks one.

export function render(table) {
  return api.get('/api/devices').then(function (result) {
    result.devices.forEach(function (device) {
      var row = table.insertRow();
      row.insertCell().textContent = device.name;
      row.insertCell().textContent = device.ip;
    });
  });
}

export function blockDevice(mac) {
  return api.post('/api/devices/' + encodeURIComponent(mac) + '/block', { isBlocked: true });
}
