// Login built by script: the token comes back as JSON and goes into localStorage.
(function () {
  var target = document.getElementById('login');
  var user = document.createElement('input');
  var pass = document.createElement('input');
  var button = document.createElement('button');
  var error = document.createElement('div');
  pass.type = 'password';
  button.textContent = 'Sign in';
  error.className = 'hint';
  button.onclick = function () {
    fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: user.value, password: pass.value })
    }).then(function (r) {
      if (!r.ok) { throw new Error('wrong user or password'); }
      return r.json();
    }).then(function (result) {
      localStorage.setItem('mockToken', result.token);
      location.href = '/';
    }).catch(function (e) { error.textContent = e.message; });
  };
  [['User', user], ['Password', pass]].forEach(function (pair) {
    var label = document.createElement('label');
    label.textContent = pair[0];
    target.append(label, pair[1]);
  });
  target.append(button, error);
})();
