var sessionId = "<redacted>";
var device = {"sid":"<redacted>","model":"<redacted>","lang":"<redacted>"};
var menuPages = ["status", "wifi", "devices", "system"];
;
function selectPage(link, name) {
  document.querySelectorAll('.menu a').forEach(function (a) { a.classList.remove('is-active'); });
  link.classList.add('is-active');
  loadPage(name);
}
;
return false;
;
selectPage(this, 'status'); return false;
;
selectPage(this, 'wifi'); return false;
;
selectPage(this, 'devices'); return false;
;
selectPage(this, 'system'); return false;