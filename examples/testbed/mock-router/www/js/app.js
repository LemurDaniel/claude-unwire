// Mock router UI: request helpers, page loader and view loader.
// window.mockAuth comes from js/auth.<method>.js: base path, query and headers per login method.

var api = {
  url: function (path, params) {
    var auth = window.mockAuth || { base: '', query: {}, headers: function () { return {}; } };
    var query = Object.assign({}, params || {}, auth.query);
    var search = new URLSearchParams(query).toString();
    return auth.base + path + (search ? '?' + search : '');
  },
  get: function (path, params) {
    var auth = window.mockAuth;
    return fetch(api.url(path, params), { headers: auth.headers() }).then(api.read);
  },
  post: function (path, body) {
    var auth = window.mockAuth;
    var headers = Object.assign({ 'Content-Type': 'application/json' }, auth.headers());
    return fetch(api.url(path), { method: 'POST', headers: headers, body: JSON.stringify(body) })
      .then(api.read);
  },
  // A 401 ends the session: the login method decides where to go (js/auth.<method>.js)
  read: function (r) {
    if (r.status === 401 && window.mockAuth.onUnauthorized) { window.mockAuth.onUnauthorized(); }
    return r.json();
  }
};

function getLogs(level) {
  return api.get('/api/logs', { level: level });
}

function getConfig(section) {
  var xhr = new XMLHttpRequest();
  xhr.open('GET', api.url('/cgi-bin/config.cgi', { section: section }));
  xhr.send();
  return xhr;
}

function setConfig(section, values) {
  var xhr = new XMLHttpRequest();
  xhr.open('POST', api.url('/cgi-bin/config.cgi', { section: section }));
  xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  xhr.send(new URLSearchParams(values).toString());
  return xhr;
}

// Pages are loaded by XHR into the main frame: "pages/" + name + ".htm"
function loadPage(name) {
  var xhr = new XMLHttpRequest();
  xhr.open('GET', 'pages/' + name + '.htm' + location.search);
  xhr.onload = function () {
    var mainDocument = top.frames['main'].document;
    var content = mainDocument.getElementById('content');
    content.innerHTML = xhr.responseText;
    // innerHTML does not run scripts: copy each one into a new element inside the main frame
    content.querySelectorAll('script').forEach(function (oldScript) {
      var script = mainDocument.createElement('script');
      script.textContent = oldScript.textContent;
      oldScript.replaceWith(script);
    });
  };
  xhr.send();
}

// Views are modules imported from a path built at runtime, with the query of the page (sid)
function loadView(name) {
  return import('./views/' + name + '.js' + location.search);
}
