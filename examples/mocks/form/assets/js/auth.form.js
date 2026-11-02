// Login form: the session cookie goes along by itself.
window.mockAuth = { base: '', query: {}, headers: function () { return {}; } };

function logout() {
  location.href = '/logout';
}
