const express = require('express');
const app = express();
const { Curl, CurlFeature, CurlHttpVersion, CurlSslVersion } = require('node-libcurl-impersonate');
const caseless = require('caseless');
const port = 3000;

/* *
 * true:  redirect request's headers, but you can change them in 
 *       `overrideHttpHeader` or add missing headers in `noOverrideHttpHeader`
 *
 * false: only request's `Content-Type`, `Cookie` and `Authorization` headers 
 *        passed to upstream. Add more allowed headers in `allowedHeaders`
 */
const reqHeadersPass = true;

const allowedHeaders = [ 'Content-Type', 'Authorization', 'Cookie' ];

const debug = process.env.DEBUG || false;

const curlRequest = async (req, res, next) => {
  try {
    const curl = new Curl();
    const close = curl.close.bind(curl);

    const targetHost = req.params.host;
    let httpHeader = [];

    const overrideHttpHeader = [
      `Authority: ${targetHost}`,
      `Host: ${targetHost}`,
      'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="99", "Google Chrome";v="99"',
      'sec-ch-ua-mobile: ?1',
      'sec-ch-ua-platform: "Android"',
      'Upgrade-Insecure-Requests: 1',
      'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      'Sec-Fetch-Site: none',
      'Sec-Fetch-Mode: navigate',
      'Sec-Fetch-User: ?1',
      'Sec-Fetch-Dest: document',
      'Accept-Encoding: gzip, deflate, br',
      'Accept-Language: en-US,en;q=0.9'
    ];

    const noOverrideHttpHeader = [
      'User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
    ];

    const options = {
      url: `${req.protocol}:/${req.originalUrl}`,
      followLocation: false,
    };

    let reqHeaders = {},
        cReqHeaders = caseless(reqHeaders);

    if (reqHeadersPass === false) {
      for (const header of allowedHeaders) {
        if (req.get(header)) {
          cReqHeaders.set(header, req.get(header), true);
        }
      }
    } else if (req.headers) {
      for (const headerName in req.headers) {
        cReqHeaders.set(headerName, req.get(headerName), true);
      }
    }

    for (const header of noOverrideHttpHeader) {
      const [name, ...values] = header.split(':');
      const headerName = name.trim();

      if (!cReqHeaders.has(headerName)) {
        cReqHeaders.set(headerName, values.join(':').trim());
      }
    }

    for (const header of overrideHttpHeader) {
      const [name, ...values] = header.split(':');
      cReqHeaders.set(name.trim(), values.join(':').trim(), true);
    }

    delete reqHeaders.connection;
    delete reqHeaders.range;
    delete reqHeaders['icy-metadata'];

    for (const headerName in reqHeaders) {
      httpHeader.push(`${headerName}: ${cReqHeaders.get(headerName)}`);
    }

    curl.enable(CurlFeature.StreamResponse);
    if (req.method === 'POST') {
      curl.setOpt('POSTFIELDS', JSON.stringify(req.body));
    }
    curl.setOpt(Curl.option.URL, options.url);
    curl.setOpt(Curl.option.FOLLOWLOCATION, options.followLocation);
    curl.setOpt(Curl.option.HTTPHEADER, httpHeader);
    curl.setOpt(Curl.option.HTTP_VERSION, CurlHttpVersion.V2_0);
    curl.setOpt(Curl.option.ACCEPT_ENCODING, 'gzip, deflate, br');
    curl.setOpt(
      Curl.option.SSL_CIPHER_LIST,
      'TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256,ECDHE-ECDSA-AES128-GCM-SHA256,ECDHE-RSA-AES128-GCM-SHA256,ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES256-GCM-SHA384,ECDHE-ECDSA-CHACHA20-POLY1305,ECDHE-RSA-CHACHA20-POLY1305,ECDHE-RSA-AES128-SHA,ECDHE-RSA-AES256-SHA,AES128-GCM-SHA256,AES256-GCM-SHA384,AES128-SHA,AES256-SHA',
    );
    curl.setOpt(Curl.option.SSLVERSION, CurlSslVersion.TlsV1_2);
    curl.setOpt(Curl.option.SSL_ENABLE_NPN, 0);
    curl.setOpt(Curl.option.SSL_ENABLE_ALPS, 1);
    curl.setOpt(Curl.option.SSL_COMPRESSION, 'brotli');
    //curl.setOpt(Curl.option.WRITEFUNCTION, (buffer) => {
    //  res.write(buffer);
    //  return buffer.length;
    //});

    let headersSent = false;

    curl.on('stream', async (stream, statusCode, headers) => {
      if (headersSent === false) {
        let resHeaders = headers[0],
            cResHeaders = caseless(resHeaders);
        if (debug) {
          console.log('resHeaders:');
          console.log(resHeaders);
          console.log('reqHeaders:');
          console.log(req.headers);
          console.log('httpHeader:');
          console.log(httpHeader);
        }
        cResHeaders.set('server', 'AIOS', true);
        const reason = resHeaders.result.reason;
        delete resHeaders.result;
        cResHeaders.set('Access-Control-Allow-Origin', `${req.protocol}://${req.hostname}:${port}`, true);
        cResHeaders.set('Access-Control-Allow-Credentials', 'true', true);
        if (cResHeaders.has('set-cookie')) {
          const cookieArray = cResHeaders.get('set-cookie').split(';').map((cookie) => {
            const [name, values] = cookie.trim().split('=');
            const value = values.join('=').trim();
            if (name === 'domain') {
              return `${name}=${req.hostname}`;
            } else if (name === 'path') {
              return `${name}=/${targetHost}${value}`;
            }
            return `${name}=${value}`;
          });
          cResHeaders.set('set-cookie', cookieArray.join('; ').trim(), true);
        }
        res.set(resHeaders);
        if (statusCode === 301 || statusCode === 302) {
          curl.close();
          const location = cResHeaders.get('location');
          const regex = /^(https?):\/\//i;
          if (regex.test(location)) {
            res.redirect(statusCode, `/${location.replace(regex, '')}`);
          } else {
            res.redirect(statusCode, `/${targetHost}/${location}`);
          }
          return;
        } else if (statusCode !== 200) {
          curl.close();
          res.status(statusCode).send(reason);
          return;
        }
        headersSent = true;
      }
      stream.on('end', () => {
        res.end();
      });
      //stream.on('error', (error) => {
      //  console.log('response stream error: ', error);
      //  res.end();
      //});
      //stream.on('close', () => {
      // console.log('response stream: close');
      //})

      // using async iterators (Node.js >= 10)
      for await (const chunk of stream) {
        res.write(chunk);
      }
    });

    curl.on('end', close);
    curl.on('error', close);

    curl.perform();
  } catch (err) {
    next(err);
  }
};

app.use('/:host', curlRequest);

app.use((err, req, res, next) => {
  res.status(400).send(err.message);
});

app.listen(port, () => {
  console.log(`listening on port ${port}`);
});
