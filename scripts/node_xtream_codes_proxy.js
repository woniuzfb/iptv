const express = require('express');
const app = express();
// node-libcurl built with libcurl-impersonate
const { Curl, CurlFeature, CurlHttpVersion, CurlSslVersion } = require('/root/node-libcurl/dist');
const { createProxyMiddleware } = require('http-proxy-middleware');
const port = 3000;

const curlRequest = async (req, res, next) => {
  try {
    const headers = [
      'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="99", "Google Chrome";v="99"',
      'sec-ch-ua-mobile: ?1',
      'sec-ch-ua-platform: "Android"',
      'Upgrade-Insecure-Requests: 1',
      'User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      'Sec-Fetch-Site: none',
      'Sec-Fetch-Mode: navigate',
      'Sec-Fetch-User: ?1',
      'Sec-Fetch-Dest: document',
      'Accept-Encoding: gzip, deflate, br',
      'Accept-Language: en-US,en;q=0.9',
      'Host: ' + req.query.host
    ];

    if (req.get('Cookie')) {
      headers.push('Cookie: ' + req.get('Cookie'))
    }

    if (req.get('Authorization')) {
      headers.push('Authorization: ' + req.get('Authorization'))
    }

    const curl = new Curl();
    const close = curl.close.bind(curl);

    curl.enable(CurlFeature.StreamResponse);
    curl.setOpt(Curl.option.URL, req.query.url);
    curl.setOpt(Curl.option.FOLLOWLOCATION, 1);
    curl.setOpt(Curl.option.HTTPHEADER, headers);
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

    curl.on('error', close);
    curl.on('end', close);

    //curl.on('end', function (status, data, headers) {
      //console.log(status, data, headers);
      //res.send(data);
      //this.close();
    //})

    curl.on('stream', async (stream, _statusCode, _headers) => {
      stream.on('end', () => {
        console.log('response stream: finished!')
      })
      stream.on('error', (error) => {
        console.log('response stream: error', error)
      })
      stream.on('close', () => {
        console.log('response stream: close')
      })

      // usinc async iterators (Node.js >= 10)
      for await (const chunk of stream) {
        res.write(chunk)
      }
      res.end()
    })

    curl.perform();
  } catch (err) {
    next(err);
  }
}

const customPath = function (path, req) {
  return '/curl?host=' + req.params.host + '&url=http:/' + req.originalUrl;
};

app.use('/curl', curlRequest);

app.use('/:host', createProxyMiddleware({
  target: `http://localhost:${port}`,
  //changeOrigin: true,
  followRedirects: false,
  //autoRewrite: true,
  pathRewrite: customPath,
  logger: console,
  cookieDomainRewrite: "localhost",
  on: {
    ProxyRes: (proxyRes, req, res) => {
        res.header("Access-Control-Allow-Origin", "http://localhost");
        res.header("Access-Control-Allow-Credentials", "true");
    },
  },
}));

app.use((err, req, res, next) => {
  res.status(400).send(err.message);
})

app.listen(port, () => {
  console.log(`listening on port ${port}`);
})
