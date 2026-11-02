// Bearer token from the login call, kept in localStorage. The code is public like in most
// single-page apps: without a token, or when the API answers 401, the UI goes to its login page.
window.mockAuth = {
  base: '',
  query: {},
  headers: function () {
    var token = localStorage.getItem('mockToken');
    return token ? { Authorization: 'Bearer ' + token } : {};
  },
  onUnauthorized: function () {
    localStorage.removeItem('mockToken');
    top.location.href = '/login.bearer.htm';
  }
};

if (!localStorage.getItem('mockToken')) {
  window.mockAuth.onUnauthorized();
}
