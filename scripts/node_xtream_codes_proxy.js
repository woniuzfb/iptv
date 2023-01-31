const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const customRouter = function (req) {
  return 'http://' + req.url.split('/')[1];
};

const customPath = function (path, req) {
  return path.substring(path.substring(1).indexOf('/') + 1);
};

const app = express();

app.use(
  '/',
  createProxyMiddleware({
    target: 'http://vip.4kiptv.pro',
    changeOrigin: true,
    followRedirects: true,
    autoRewrite: true,
    router: customRouter,
    pathRewrite: customPath,
    logger: console,
    cookieDomainRewrite: "localhost",
    on: {
      ProxyRes: (proxyRes, req, res) => {
          res.header("Access-Control-Allow-Origin", "http://localhost");
          res.header("Access-Control-Allow-Credentials", "true");
      },
    },
  })
);

app.listen(3000);
