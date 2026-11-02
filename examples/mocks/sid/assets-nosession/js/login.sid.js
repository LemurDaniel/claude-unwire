// Login built by script: no password field in the HTML, the session comes back as sid.

function field(target, text, input) {
  var label = document.createElement('label');
  label.textContent = text;
  target.append(label, input);
}

export function showLogin(target) {
  var user = document.createElement('input');
  var pass = document.createElement('input');
  var button = document.createElement('button');
  pass.type = 'password';
  button.textContent = 'Sign in';
  button.onclick = function () {
    fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ username: user.value, password: pass.value }).toString()
    }).then(function (r) { return r.json(); }).then(function (result) {
      location.href = '/index.htm?sid=' + result.sid;
    });
  };
  field(target, 'User', user);
  field(target, 'Password', pass);
  target.append(button);
}
