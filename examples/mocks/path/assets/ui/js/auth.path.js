// Session token as a path segment: '/ui/;tok=<VALUE>/main.htm' => base '/ui/;tok=<VALUE>'
var tokenBase = location.pathname.match(/^\/ui\/;tok=[^\/]+/)[0];
window.mockAuth = { base: tokenBase, query: {}, headers: function () { return {}; } };
