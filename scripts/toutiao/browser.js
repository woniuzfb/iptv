const { chromium, devices } = require('playwright-chromium');
const desktop = devices["Desktop Chrome"];

const url = process.argv[2];
const cookies = process.argv[3];

const RESOURCE_EXCLUSIONS = ['image', 'stylesheet', 'media', 'font'];
const URL_EXCLUSIONS = [/zijieapi/, /log-sdk/, /secsdk-captcha/, /ibytedapm.com\/slardar\/fe\/sdk-web\/plugins/, /www.toutiao.com\/ttwid\/check/, /www.toutiao.com\/ttwid\/report_fingerprint/, /helpdesk.bytedance.com/];

class Utils {
  static getRandomInt(a, b) {
    const min = Math.min(a, b);
    const max = Math.max(a, b);
    const diff = max - min + 1;
    return min + Math.floor(Math.random() * Math.floor(diff));
  }

  static isUrl(url) {
    try {
      new URL(url);
      return true;
    } catch (e) {
      return false;
    }
  }
}

class Signer {
  userAgent =
    "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  args = [
    "--disable-blink-features",
    "--disable-blink-features=AutomationControlled",
    "--disable-infobars",
    "--window-size=1920,1080",
    "--start-maximized",
  ];

  default_url = "https://www.toutiao.com/c/user/token/MS4wLjABAAAAB2ev2na9xNHI8py8dnKvLnSYGkxaFKDtOQTqbR7nsEzpNhwVqpCY8ZZz6s7qA8vt/";

  constructor(default_url, userAgent, browser) {
    if (default_url) {
      this.default_url = default_url;
    }
    if (userAgent) {
      this.userAgent = userAgent;
    }

    if (browser) {
      this.browser = browser;
      this.isExternalBrowser = true;
    }

    this.args.push(`--user-agent="${this.userAgent}"`);

    this.options = {
      headless: true,
      args: this.args,
      ignoreDefaultArgs: ["--mute-audio", "--hide-scrollbars"],
      ignoreHTTPSErrors: true,
    };
  }

  async init() {
    try {
      if (!this.browser) {
        this.browser = await chromium.launch(this.options);
      }

      let emulateTemplate = {
        ...desktop,
        locale: "en-US",
        isMobile: false,
        hasTouch: false,
        userAgent: this.userAgent,
      };

      emulateTemplate.viewport.width = Utils.getRandomInt(1280, 1920);
      emulateTemplate.viewport.height = Utils.getRandomInt(1280, 1920);

      this.context = await this.browser.newContext({
        bypassCSP: true,
        devtools: true,
        ...emulateTemplate,
      });

      this.page = await this.context.newPage();

      await this.page.route("**/*", (route) => {
        const url = route.request().url();
        const isExcluded = URL_EXCLUSIONS.some(regex => regex.test(url));
        if (RESOURCE_EXCLUSIONS.includes(route.request().resourceType()) || isExcluded) {
          return route.abort();
        }
        return route.continue();
      });

      const getinfoRequestPromise = this.page.waitForRequest('https://xxbg.snssdk.com/websdk/v1/getInfo*');
      const feedRequestPromise = this.page.waitForRequest('https://www.toutiao.com/api/pc/list/user/feed?category=profile_all*');

      await this.page.goto(this.default_url, {
        waitUntil: "networkidle",
      });

      const getinfoRequest = await getinfoRequestPromise;
      const feedRequest = await feedRequestPromise;

      await this.page.evaluate(() => {
        window.generateSignature = function generateSignature(url,string) {
          if (typeof window.byted_acrawler.sign !== "function") {
            throw "No signature function found";
          }
          return string ? window.byted_acrawler.sign("", string) : window.byted_acrawler.sign({ url: url });
        };

        window.generateBogus = function generateBogus(params) {
          if (typeof window.byted_acrawler.generateBogus !== "function") {
            throw "No X-Bogus function found";
          }
          return window.byted_acrawler.generateBogus(params);
        };

        return this;
      });

      let LOAD_SCRIPTS = ["xbogus.js"];
      await Promise.all(LOAD_SCRIPTS.map(async (script) => {
        await this.page.addScriptTag({
          path: `${__dirname}/${script}`,
        });
        //console.log("[+] " + script + " loaded");
      }));

      return {
        feed: {
          url: feedRequest.url(),
          headers: feedRequest.headers(),
        },
        getinfo: {
          url: getinfoRequest.url(),
          headers: getinfoRequest.headers(),
        },
      };
    } catch (error) {
      process.exit(1);
    }
  }

  async sign(link, cookies) {
    await this.context.addCookies(cookies);
    let token;
    if (Utils.isUrl(link)) {
      token = await this.page.evaluate(`generateSignature("","${link}")`);
      let signed_url = link + "&_signature=" + token;
      let queryString = new URL(signed_url).searchParams.toString();
      let bogus = await this.page.evaluate(`generateBogus("${queryString}","${this.userAgent}")`);
      return {
        signature: token,
        "x-bogus": bogus,
        signed_url: signed_url,
      };
    }
    token = await this.page.evaluate(`generateSignature("${link}")`);
    return {
      signature: token,
    };
  }

  async close() {
    if (this.browser && !this.isExternalBrowser) {
      await this.browser.close();
      this.browser = null;
    }
    if (this.page) {
      this.page = null;
    }
  }
}

(async function main() {
  try {
    const signer = new Signer();
    const init = await signer.init();
    let output;

    if (cookies) {
      const sign = await signer.sign(url, JSON.parse(cookies));

      output = JSON.stringify({
        status: "ok",
        data: {
          ...init,
          ...sign,
        },
      });
    } else {
      output = JSON.stringify({
        status: "ok",
        data: {
          ...init,
        },
      });
    }

    console.log(output);
    await signer.close();
  } catch (err) {
    console.error(err);
  }
})();
