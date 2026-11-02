api.get('/api/wifi').then(function (wifi) {
  document.querySelector('#wifi [name=ssid]').value = wifi.ssid;
});
function setWifi(ssid, channel, isEnabled) {
  return api.post('/api/wifi', { ssid: ssid, channel: channel, isEnabled: isEnabled });
}