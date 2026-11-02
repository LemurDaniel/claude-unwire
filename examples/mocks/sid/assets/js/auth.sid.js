// Session in the URL parameter sid, taken from the page URL.
var sid = new URLSearchParams(location.search).get('sid');
window.mockAuth = { base: '', query: { sid: sid }, headers: function () { return {}; } };
