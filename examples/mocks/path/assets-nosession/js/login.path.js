// Login built by script: the token comes back and goes into the path of every page.
(function () {
  var target = document.getElementById('login');
  var user = document.createElement('input');
  var pass = document.createElement('input');
  var button = document.createElement('button');
  pass.type = 'password';
  button.textContent = 'Sign in';
  button.onclick = function () {
    fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: user.value, password: pass.value })
    }).then(function (r) { return r.json(); }).then(function (result) {
      location.href = '/ui/;tok=' + result.token + '/index.htm';
    });
  };
  [['User', user], ['Password', pass]].forEach(function (pair) {
    var label = document.createElement('label');
    label.textContent = pair[0];
    target.append(label, pair[1]);
  });
  target.append(button);
})();
