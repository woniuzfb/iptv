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
const ALLOW_UPSTREAMS = []

// delete request headers, such as "Origin", "Referer", "Cookie", "CF-IPCountry", "CF-Connecting-IP", 
// "CF-Request-ID", "X-Real-IP", "X-Forwarded-For", "CF-Ray", "CF-Visitor", "X-Forwarded-Proto"
const DELETE_REQUEST_HEADERS = ["Origin", "Referer", "CF-IPCountry", "CF-Connecting-IP",
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

async function getSetCookie(request, response) {
  let result = ""

  if (!response) {
    return result
  }

  const responseCookieString = response.headers.get("Set-Cookie")
  if (!responseCookieString) {
    return result
  }

  const responseCookie = responseCookieString.split(";")[0].trim()

  const requestCookieString = request.headers.get("Cookie")
  if (!requestCookieString) {
    return responseCookie
  }

  const responseCookiePair = responseCookie.split("=", 2)
  const requestCookies = requestCookieString.split(";")

  let found = 0

  for (let index = 0; index < requestCookies.length; index++) {
    const requestCookie = requestCookies[index];
    const requestCookiePair = requestCookie.split("=", 2)
    const requestCookieName = requestCookiePair[0].trim()
    result = (result ? result + "; " : "") + requestCookieName + "="
    if (requestCookieName === responseCookiePair[0]) {
      result = result + responseCookiePair[1]
      found = 1
    }
    else {
      result = result + requestCookiePair[1]
    }
  }

  if (found === 0) {
    return result + "; " + responseCookie
  }

  return result
}

async function handleRequest(request) {
  const BLOCK_ACCESS_RESPONSE = new Response("Access denied", { status: 403 })
  const BLOCK_REGION_RESPONSE = new Response("Region denied", { status: 403 })
  const BLOCK_IP_RESPONSE = new Response("IP denied", { status: 403 })
  const BLOCK_URL_RESPONSE = new Response("URL denied", { status: 403 })
  const NO_PROFILE_RESPONSE = new Response("NO profile", { status: 401 })
  const NO_GENRES_RESPONSE = new Response("NO genres", { status: 401 })
  //const NO_ACCOUNT_RESPONSE = new Response("NO account info", { status: 401 })

  const requestURL = new URL(request.url)
  const check = requestURL.searchParams.get("check") || 0
  requestURL.searchParams.delete("check")
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

  let upstreamInit = {
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
  const cmd = upstreamURL.searchParams.get("cmd")
  const auth = upstreamURL.searchParams.get("auth")

  let setCookie

  if (auth) {
    upstreamRequest.headers.set("Authorization", "Bearer " + auth)
    upstreamURL.searchParams.delete("auth")

    const params = ["mac","stb_lang","timezone","play_token","token"]

    for (const pair of upstreamURL.searchParams.entries()) {
      if (!params.includes(pair[0])) {
        upstreamRequest.headers.set("Cookie", upstreamRequestCookieString + "; " + pair[0] + "=" + pair[1])
        upstreamURL.searchParams.delete(pair[0])
      }
    }

    upstream = upstreamURL.href
  }
  else if (cmd) {
    upstream = upstreamURL.origin
    const tokenURL = upstream + "/portal.php?type=stb&action=handshake"
    const profileURL = upstream + "/portal.php?type=stb&action=get_profile"
    const genresURL = upstream + "/portal.php?type=itv&action=get_genres"
    //const accountURL = upstream + "/portal.php?type=account_info&action=get_main_info"
    const cmdURL = upstream + "/portal.php?type=itv&action=create_link&cmd=" + cmd

    upstreamRequest.headers.delete("Authorization")

    const accessTokenRes = await fetch(tokenURL, upstreamRequest)
    const accessTokenJson = await accessTokenRes.json()
    const accessToken = accessTokenJson.js.token

    upstreamRequest.headers.set("Authorization", "Bearer " + accessToken)

    setCookie = await getSetCookie(upstreamRequest, accessTokenRes)
    if (setCookie) {
      upstreamRequest.headers.set("Cookie", setCookie)
    }

    const profileRes = await fetch(profileURL, upstreamRequest)
    const profileJson = await profileRes.json()

    setCookie = await getSetCookie(profileRes)
    if (setCookie) {
      upstreamRequest.headers.set("Cookie", setCookie)
    }

    const genresRes = await fetch(genresURL, upstreamRequest)
    const genresJson = await genresRes.json()

    if (!genresJson) {
      if (!profileJson) {
        return NO_PROFILE_RESPONSE
      }
      return NO_GENRES_RESPONSE
    }

    setCookie = await getSetCookie(genresRes)
    if (setCookie) {
      upstreamRequest.headers.set("Cookie", setCookie)
    }

    //const accountRes = await fetch(accountURL, upstreamRequest)
    //const accountJson = await accountRes.json()

    //if (!accountJson) {
    //  return NO_ACCOUNT_RESPONSE
    //}

    await new Promise(resolve => setTimeout(resolve, 2000));

    const cmdRes = await fetch(cmdURL, upstreamRequest)
    const cmdJson = await cmdRes.json()

    const cmdLink = cmdJson.js.cmd.split(" ").pop()
    const cmdLinkArr = cmdLink.split("/")

    const upstreamLink = cmdLinkArr[0] + "//" + cmdLinkArr[2] + "/" + cmdLinkArr[3] + "/" + cmdLinkArr[4] + "/" + cmdLinkArr[cmdLinkArr.length - 1]

    setCookie = await getSetCookie(cmdRes)
    if (setCookie) {
      upstreamRequest.headers.set("Cookie", setCookie)
    }

    try {
      upstreamURL = new URL(upstreamLink)
    } catch (error) {
      let body = {
        cmd: cmd,
        cmdJson: cmdJson,
        upstream: upstream,
        upstreamLink: upstreamLink,
        accessToken: accessToken
      }
      return new Response(JSON.stringify(body), {
        status: 200,
        headers: {
          "content-type": "application/json;charset=UTF-8",
        }
      })
    }

    upstream = upstreamLink
  }

  const originalResponse = await fetch(upstream, upstreamRequest)
  const contentType = originalResponse.headers.get("content-type") || ""
  let location = originalResponse.headers.get("Location")

  setCookie = await getSetCookie(originalResponse)
  if (setCookie) {
    upstreamRequest.headers.set("Cookie", setCookie)
  }

  const cookieString = upstreamRequest.headers.get("Cookie") || ""

  if (location) {
    const locationURL = new URL(location)
    const { host } = locationURL

    const accessToken = upstreamRequest.headers.get("Authorization") || ""

    if (!host.match(/[a-z]/i)) {
      const body = {
        streamLink: location,
        accessToken: accessToken.slice(7),
        cookies: cookieString
      }
      return new Response(JSON.stringify(body), {
        status: 200,
        headers: {
          "content-type": "application/json;charset=UTF-8",
        }
      })
    }

    if (accessToken) {
      locationURL.searchParams.append("auth", accessToken.slice(7))
    }

    if (cookieString) {
      const params = ["mac","stb_lang","timezone"]
      const cookies = cookieString.split(";")

      for (let index = 0; index < cookies.length; index++) {
        const cookie = cookies[index];
        const cookiePair = cookie.split("=", 2)
        const cookieName = cookiePair[0].trim()
        if (!params.includes(cookieName)) {
          locationURL.searchParams.append(cookieName, cookiePair[1])
        }
      }
    }

    if (check) {
      locationURL.searchParams.append("check", 1)
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

    if (check) {
      const accessToken = upstreamRequest.headers.get("Authorization") || ""

      const body = {
        streamLink: upstream,
        accessToken: accessToken.slice(7),
        cookies: cookieString
      }

      return new Response(JSON.stringify(body), {
        status: 200,
        headers: {
          "content-type": "application/json;charset=UTF-8",
        }
      })
    }

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
  const headers = request.headers;
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
  const url = new URL(request.url)
  if(url.pathname.startsWith(PROXY_ENDPOINT)){
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