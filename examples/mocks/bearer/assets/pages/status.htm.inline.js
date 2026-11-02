api.get('/api/status').then(function (status) {
  document.getElementById('version').textContent = status.version;
  document.getElementById('wan').textContent = status.wan.ip;
  document.getElementById('uptime').textContent = Math.round(status.uptime / 3600) + ' h';
});