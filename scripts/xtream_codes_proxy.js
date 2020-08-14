// Website you intended to retrieve for users. OR set request header 'xc_host'
let upstream = 'livegopanel.club:8080'

// Custom pathname for the upstream website.
const upstream_path = '/'

// Countries and regions where you wish to suspend your service.
const blocked_region = []

// IP addresses which you wish to block from using your service.
const blocked_ip_address = ['0.0.0.0', '127.0.0.1']

addEventListener('fetch', event => {
  event.respondWith(fetchAndApply(event.request));
})

async function fetchAndApply(request) {
  let redirect = 'follow';
  let request_headers = request.headers;
  if (request_headers.get('xc_host')) {
    upstream = request_headers.get('xc_host');
  }
  const region = request_headers.get('cf-ipcountry').toUpperCase();
  const ip_address = request_headers.get('cf-connecting-ip');
  const cmd = request_headers.get('cmd');
  const redirect_header = request_headers.get('redirect');

  let new_request_headers = new Headers(request_headers);
  new_request_headers.delete('xc_host');
  new_request_headers.delete('cf-ipcountry');
  new_request_headers.delete('cf-connecting-ip');
  new_request_headers.delete('cf-request-id');
  new_request_headers.delete('x-real-ip');
  new_request_headers.delete('x-forwarded-for');
  new_request_headers.delete('cf-ray');
  new_request_headers.delete('cf-visitor');
  new_request_headers.delete('x-forwarded-proto');
  new_request_headers.set('Host', upstream);

  let url = new URL(request.url);
  let response = null;
  if (redirect_header) {
    url.href = 'http://' + upstream + '/' + redirect_header;
    new_request_headers.delete('redirect');
  } else {
    if (url.pathname == '/') {
      url.pathname = upstream_path;
    } else {
      url.pathname = upstream_path + url.pathname;
    }
    url.host = upstream;
    url.protocol = 'http:';
  }

  if (blocked_region.includes(region)) {
    response = new Response('Access denied.', {
      status: 403
    });
  } else if (blocked_ip_address.includes(ip_address)) {
    response = new Response('Access denied.', {
      status: 403
    });
  } else {

    if (cmd) {
      const token_url = 'http://' + upstream + '/portal.php?type=stb&action=handshake&JsHttpRequest=1-xml';
      const profile_url = 'http://' + upstream + '/portal.php?type=stb&action=get_profile&JsHttpRequest=1-xml';
      const create_link_url = 'http://' + upstream + '/portal.php?type=itv&action=create_link&cmd=' + cmd + '&series=&forced_storage=undefined&disable_ad=0&download=0&JsHttpRequest=1-xml'

      new_request_headers.delete('Authorization');
      new_request_headers.delete('cmd');

      const token_res = await fetch(token_url, {
        headers: new_request_headers
      });
      const token_json = await token_res.json();
      let token = token_json.js.token;

      new_request_headers.set('Authorization', 'Bearer ' + token);
      const access_token_res = await fetch(token_url, {
        headers: new_request_headers
      });
      const access_token_json = await access_token_res.json();
      let access_token = access_token_json.js.token;

      new_request_headers.set('Authorization', 'Bearer ' + access_token);
      const profile_res = await fetch(profile_url, {
        headers: new_request_headers
      });
      const profile_json = await profile_res.json();

      if (!profile_json) {
        return new Response('Access denied.', {
          status: 401
        });
      }

      const stream_link_res = await fetch(create_link_url, {
        headers: new_request_headers
      });

      const stream_link_json = await stream_link_res.json();
      let stream_link_cmd = stream_link_json.js.cmd.split(' ')[1];
      let cmd_link = stream_link_cmd.split('/');

      let stream_link_url = new URL(cmd_link[0] + '//' + cmd_link[2] + '/' + cmd_link[3] + '/' + cmd_link[4] + '/' + cmd_link[cmd_link.length - 1]);

      url.href = stream_link_url.href;

      new_request_headers.set('Host', stream_link_url.host);

      redirect = 'manual';
    }

    const original_response = await fetch(url.href, {
      headers: new_request_headers,
      redirect: redirect
    });

    let response_headers = original_response.headers;
    const content_type = response_headers.get('content-type');

    if (content_type != null && (content_type.includes('video') || content_type.includes('stream') || content_type.includes('zip'))) {
      let { readable, writable } = new TransformStream();
      original_response.body.pipeTo(writable);
      response = new Response(readable, original_response);
    } else {
      const body = await original_response.text();
      response = new Response(body, original_response);
    }
  }
  return response;
}
