getLogs('warn').then(function (logs) {
  document.getElementById('logs').textContent = JSON.stringify(logs.entries, null, 2);
});
getConfig('lan');
;
api.post('/api/reboot', {})