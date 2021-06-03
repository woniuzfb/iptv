// Stream Proxy For https://github.com/woniuzfb/iptv
const VERSION = "0.1.0"

// Empty: flexible upstream domain, e.g. http://yourworker-domain.dev/PROXY_ENDPOINT/https://any.upstream-domain.com/upstream-path
// Not Empty: secure, fixed upstream domain, e.g. http://yourworker-domain.dev/PROXY_ENDPOINT/upstream-path
const UPSTREAM_DOMAIN = ""

// Effect if UPSTREAM_DOMAIN not empty
const UPSTREAM_HTTPS = false

// The endpoint you want the (CORS) reverse proxy to be on
const PROXY_ENDPOINT = "/proxy/"

// Countries and regions you wish to block from using your service
const BLOCK_REGIONS = []

// Only allow these regions
const ALLOW_REGIONS = []

// IP addresses you wish to block from using your service
const BLOCK_IPS = ["0.0.0.0", "127.0.0.1"]

// Only allow these IPs
const ALLOW_IPS = []

// Origin domains you wish to block from using your service
const BLOCK_ORIGINS = []

// Origin domains
const ALLOW_ORIGINS = []

// Upstream domains
const ALLOW_UPSTREAMS = ["api.fengshows.cn", "dis.fengshows.cn", "tlive.fengshows.cn", "hlive.fengshows.cn", "qlive.fengshows.cn"]

// Choose fengshows CDN: tlive, hlive, qlive
const FENGSHOWS_CDN = "tlive"

// delete request headers, such as "Origin", "Referer", "Cookie", "CF-IPCountry", "CF-Connecting-IP", 
// "CF-Request-ID", "X-Real-IP", "X-Forwarded-For", "CF-Ray", "CF-Visitor", "X-Forwarded-Proto"
const DELETE_REQUEST_HEADERS = ["Origin", "Referer", "Cookie", "CF-IPCountry", "CF-Connecting-IP",
"CF-Request-ID", "X-Real-IP", "X-Forwarded-For", "CF-Ray", "CF-Visitor", "X-Forwarded-Proto"]

// set request header Origin to upstream
const SET_HEADER_ORIGIN = false

// The redirect mode to use: follow, error, manual
const REQUEST_REDIRECT = "manual"

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,HEAD,POST,OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Access-Control-Allow-Credentials": true,
}

const INDEX_PAGE = `
  <!DOCTYPE html>
  <html>
  <body>
    <h1>Stream Proxy For <a target="_blank" href="https://github.com/woniuzfb/iptv">IPTV</a></h1>
  </body>
  </html>`

async function rawHtmlResponse(html) {
  return new Response(html, {
    headers: {
      "content-type": "text/html;charset=UTF-8",
    },
  })
}

async function handleRequest(request) {
  const BLOCK_ACCESS_RESPONSE = new Response("Access denied", { status: 403 })
  const BLOCK_REGION_RESPONSE = new Response("Region denied", { status: 403 })
  const BLOCK_IP_RESPONSE = new Response("IP denied", { status: 403 })
  const BLOCK_URL_RESPONSE = new Response("URL denied", { status: 403 })

  const requestURL = new URL(request.url)
  const endpoint = PROXY_ENDPOINT.substr(PROXY_ENDPOINT.length - 1) === "/" ? PROXY_ENDPOINT : PROXY_ENDPOINT + "/"
  let upstream = requestURL.pathname.substr(endpoint.length) + requestURL.search

  if (UPSTREAM_DOMAIN) {
    upstream = (UPSTREAM_HTTPS ? "https://" : "http://") + UPSTREAM_DOMAIN + '/' + upstream
  }
  else if (upstream.substr(0,6) === "http:/") {
    upstream = "http://" + upstream.substr(6)
  }
  else if (upstream.substr(0,7) === "https:/") {
    upstream = "https://" + upstream.substr(7)
  }
  else {
    return BLOCK_URL_RESPONSE
  }

  // for fengshows
  if (!upstream.startsWith("https://api.")) {
    upstream = "http://" + FENGSHOWS_CDN + upstream.substr(upstream.indexOf("."))
  }

  let upstreamURL

  try {
    upstreamURL = new URL(upstream)
  }
  catch (error) {
    return BLOCK_URL_RESPONSE
  }

  if (!upstreamURL.hostname.match(/[a-z]/i)) {
    return BLOCK_URL_RESPONSE
  }

  if (ALLOW_UPSTREAMS.length && !ALLOW_UPSTREAMS.includes(upstreamURL.hostname)) {
    return BLOCK_URL_RESPONSE
  }

  let requestRegion = request.headers.get("CF-IPCountry")
  const requestIP = request.headers.get("CF-Connecting-IP")
  const requestOrigin = request.headers.get("Origin")

  if (requestRegion) {
    requestRegion = requestRegion.toUpperCase()
    if (ALLOW_REGIONS.length && !ALLOW_REGIONS.includes(requestRegion)) {
      return BLOCK_REGION_RESPONSE
    }
    else if (BLOCK_REGIONS.includes(requestRegion)) {
      return BLOCK_REGION_RESPONSE
    }
  }

  if (requestIP) {
    if (ALLOW_IPS.length && !ALLOW_IPS.includes(requestIP)) {
      return BLOCK_IP_RESPONSE
    }
    else if (BLOCK_IPS.includes(requestIP)) {
      return BLOCK_IP_RESPONSE
    }
  }

  if (requestOrigin) {
    let requestOriginURL
    try {
      requestOriginURL = new URL(requestOrigin)
    } catch (error) {
      return BLOCK_ACCESS_RESPONSE
    }
    if (ALLOW_ORIGINS.length && !ALLOW_ORIGINS.includes(requestOriginURL.hostname)) {
      return BLOCK_ACCESS_RESPONSE
    }
    else if (BLOCK_ORIGINS.includes(requestOriginURL.hostname)) {
      return BLOCK_ACCESS_RESPONSE
    }
  }

  const upstreamInit = {
    method: request.method,
    headers: request.headers,
    redirect: REQUEST_REDIRECT,
  }

  const upstreamRequest = new Request(upstream, upstreamInit)

  if (SET_HEADER_ORIGIN) {
    upstreamRequest.headers.set("Origin", upstreamURL.origin)
  }

  DELETE_REQUEST_HEADERS.forEach(requestHeader => {
    upstreamRequest.headers.delete(requestHeader)
  })

  const upstreamRequestCookieString = upstreamRequest.headers.get("Cookie")
  let newCookiesNameString = upstreamURL.searchParams.get("newCookies") || ""
  let newCookiesName
  let newCookiesValue = []

  if (newCookiesNameString) {
    newCookiesName = newCookiesNameString.split(",")
    let newCookieString = ""

    for (let index = 0; index < newCookiesName.length; index++) {
      const newCookieName = newCookiesName[index]
      const newCookieValue = upstreamURL.searchParams.get(newCookieName)
      newCookiesValue.push(newCookieValue)
      newCookieString = (newCookieString ? newCookieString + "; " : "") + newCookieName + "=" + newCookieValue
      upstreamURL.searchParams.delete(newCookieName)
    }

    upstreamRequest.headers.set("Cookie", (upstreamRequestCookieString ? upstreamRequestCookieString + "; " : "") + newCookieString)
    upstreamURL.searchParams.delete("newCookies")
    upstream = upstreamURL.href
  }

  const originalResponse = await fetch(upstream, upstreamRequest)
  const contentType = originalResponse.headers.get("Content-Type") || ""
  let location = originalResponse.headers.get("Location")

  if (location) {
    const locationURL = new URL(location)
    const { host } = locationURL

    if (!host.match(/[a-z]/i)) {
      return new Response(location, originalResponse)
    }

    if (newCookiesNameString) {
      for (let index = 0; index < newCookiesName.length; index++) {
        const newCookieName = newCookiesName[index]
        const newCookieValue = newCookiesValue[index]
        if (!locationURL.searchParams.get(newCookieName)) {
          locationURL.searchParams.append(newCookieName, newCookieValue)
        }
      }
    }

    const setCookieString = originalResponse.headers.get("Set-Cookie")

    if (setCookieString) {
      const setCookie = setCookieString.split(";")[0].trim()
      const setCookiePair = setCookie.split("=", 2)
      locationURL.searchParams.append(setCookiePair[0], setCookiePair[1])
      newCookiesNameString = (newCookiesNameString ? newCookiesNameString + "," : "") + setCookiePair[0]
    }

    if (newCookiesNameString) {
      locationURL.searchParams.append("newCookies", setCookiePair[0])
    }

    location = requestURL.origin + endpoint + locationURL.href

    const response = new Response(originalResponse)
    response.headers.set("Location", location)

    return new Response(null, {
      status: originalResponse.status,
      headers: response.headers
    })
  }

  let response

  if (contentType.includes("video") || contentType.includes("stream") || contentType.includes("zip")) {
    let { readable, writable } = new TransformStream()
    originalResponse.body.pipeTo(writable)
    response = new Response(readable, originalResponse)
  }
  else if (contentType.includes("application/json")) {
    const body = JSON.stringify(await originalResponse.json())
    response = new Response(body, originalResponse)
  }
  else {
    const body = await originalResponse.text()
    response = new Response(body, originalResponse)
  }

  if (requestOrigin) {
    response.headers.set("Access-Control-Allow-Origin", requestOrigin)
  }

  response.headers.set("Access-Control-Allow-Credentials", true)
  response.headers.append("Vary", "Origin")

  return response
}

function handleOptions(request) {
  const headers = request.headers
  if (
    headers.get("Origin") !== null &&
    headers.get("Access-Control-Request-Method") !== null &&
    headers.get("Access-Control-Request-Headers") !== null
  ){
    const respHeaders = {
      ...CORS_HEADERS,
      "Access-Control-Allow-Headers": headers.get("Access-Control-Request-Headers"),
    }
    return new Response(null, {
      headers: respHeaders,
    })
  }
  else {
    return new Response(null, {
      headers: {
        Allow: "GET, HEAD, POST, OPTIONS",
      },
    })
  }
}

addEventListener("fetch", event => {
  const request = event.request
  const requestURL = new URL(request.url)
  if(requestURL.pathname.startsWith(PROXY_ENDPOINT)){
    if (request.method === "OPTIONS") {
      event.respondWith(handleOptions(request))
    }
    else if(
      request.method === "GET" ||
      request.method === "HEAD" ||
      request.method === "POST"
    ){
      event.respondWith(handleRequest(request))
    }
    else {
      event.respondWith(
        new Response(null, {
          status: 405,
          statusText: "Method Not Allowed",
        }),
      )
    }
  }
  else {
    event.respondWith(rawHtmlResponse(INDEX_PAGE))
  }
})