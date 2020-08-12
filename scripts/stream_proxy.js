// Website you intended to retrieve for users.
const upstream = ''

// Custom pathname for the upstream website.
const upstream_path = '/'

// Countries and regions where you wish to suspend your service.
const blocked_region = []

// IP addresses which you wish to block from using your service.
const blocked_ip_address = ['0.0.0.0', '127.0.0.1']

// Whether to use HTTPS protocol for upstream address.
const https = false

addEventListener('fetch', event => {
  event.respondWith(fetchAndApply(event.request));
})

async function fetchAndApply(request) {
  const region = request.headers.get('cf-ipcountry').toUpperCase();
  const ip_address = request.headers.get('cf-connecting-ip');

  let response = null;
  let url = new URL(request.url);
  url.host = upstream;

  if (https == true) {
    url.protocol = 'https:';
  } else {
    url.protocol = 'http:';
  }

  if (url.pathname == '/') {
    url.pathname = upstream_path;
  } else {
    url.pathname = upstream_path + url.pathname;
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

    const original_response = await fetch(url.href, request);

    const response_headers = original_response.headers;
    const content_type = response_headers.get('content-type');

    if (content_type != null && (content_type.includes('video') || content_type.includes('stream') || content_type.includes('zip'))) {
      let { readable, writable } = new TransformStream();
      original_response.body.pipeTo(writable);
      response = new Response(readable, original_response);
    } else {
      const readable = await original_response.text();
      response = new Response(readable, original_response);
    }
  }
  return response;
}

