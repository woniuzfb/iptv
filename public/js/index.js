function makeStr(num) {
  let text = "";
  let possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  for (let i = 0; i < num; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}

function toggleClass(s,n) {
  let elements = document.querySelectorAll(s);
  for (let i = 0; i < elements.length; i++) {
    elements[i].classList.toggle(n);
  }
}

function switchSource(e) {
  if(e.target && e.target.nodeName === "LI") {
    sourceReg =  e.target.classList[0].substring(7);
    updateAside();
    programId = undefined;
  }
}

function switchCategory(e) {
  if(e.target && e.target.nodeName === "LI") {
    let catValue =  e.target.dataset.value;
    switch (catValue) {
      case "0":
      case "1":
        if(catValue === "0") {
          e.target.textContent = '开灯';
          e.target.dataset.value = 1;
          localStorage.setItem('dark', 1);
        } else {
          e.target.textContent = '关灯';
          e.target.dataset.value = 0;
          localStorage.setItem('dark', 0);
        }
        toggleClass('li','white');
        toggleClass('button','white');
        toggleClass('input','white');
        toggleClass('footer','white');
        toggleClass('a','white');
        toggleClass('body','bgBlack');
        toggleClass('input','bgBlack');
        toggleClass('footer','bgBlack');
        break;
      default:
        if (e.target.dataset.source) {
          sourceReg = e.target.dataset.source;
          programId = catValue;
          playVideo();
          const selected = document.querySelector('.selected');
          if(selected) selected.classList.remove('selected');
          e.target.classList.add('selected');
        } else {
          const mylist = document.querySelector('.'+catValue);
          let siblings = mylist.parentNode.childNodes;
          for(let i=0; i < siblings.length; i++) {
            if(siblings[i].nodeName === "UL") {
              siblings[i].classList.add('hidden');
            }
          }
          mylist.classList.remove('hidden');
        }
        break;
    }
  }
}

function switchChannel(e) {
  if(e.target) {
    if (e.target.nodeName === "LI") {
      sourceReg =  e.target.dataset.source;
      programId =  e.target.dataset.value;
      playVideo();
      const selected = document.querySelector('.selected');
      if(selected) selected.classList.remove('selected');
      e.target.classList.add('selected');
    } else if (e.target.nodeName === "SUB") {
      sourceReg =  e.target.parentNode.dataset.source;
      programId =  e.target.parentNode.dataset.value;
      playVideo();
      const selected = document.querySelector('.selected');
      if(selected) selected.classList.remove('selected');
      e.target.parentNode.classList.add('selected');
    }
  }
}

function videojsLoad() {
  if (videoField.hasChildNodes()) {
    videojs('video').dispose();
  }
  
  const video = document.createElement('video');
  video.id = 'video';
  video.className = 'video-js';
  const noVideojs = document.createElement('p');
  noVideojs.className = 'vjs-no-js';
  const noVideojsText = document.createTextNode('需启用 JavaScript，或使用更新的浏览器');
  noVideojs.appendChild(noVideojsText);
  video.appendChild(noVideojs);
  videoField.appendChild(video);

  var player = videojs('video',{
    liveui: liveui,
    autoplay: 'true',
    preload: 'auto',
    textTrackSettings: false,
    controls: true,
    fluid: true
  });

  player.src({
    src: hlsVideoUrl,
    type: 'application/vnd.apple.mpegurl',
    overrideNative: true
  });

  player.ready(function() {
    let promise = player.play();

    if (promise !== undefined) {
      promise.then(function() {
        // Autoplay started!
      }).catch(function(error) {
        // Autoplay was prevented.
      });
    }
  });

  player.on('error', function(e) {
    let time = this.currentTime();
    if (this.error().code === 2) {
      alertInfo('频道发生错误！',10);
      this.error(null).pause().load().currentTime(time).play();
    } else if (this.error().code === 4) {
      alertInfo('频道不可用！请重新登录账号后尝试!',10);
      /*
      if (programId) {
        localStorage.removeItem(sourceReg+'_acc');
        localStorage.removeItem(sourceReg+'_pwd');
        localStorage.removeItem(sourceReg+'_token');
        localStorage.removeItem(sourceReg+'_deviceno');
      }
      */
    } else {
      alertInfo('无法连接直播源！',10);
    }
  });
}

function playVideo() {
  if(!programId) {
    hlsVideoUrl = sourcesJsonParsed.hbo.channels[0].url;
    resetSourceReg();
    videojsLoad();
  } else if (jsonChannels[sourceReg]) {
    hlsVideoUrl = jsonChannels[sourceReg][programId];
    resetSourceReg();
    videojsLoad();
  } else if (!sourcesJsonParsed.hasOwnProperty(sourceReg) || !sourcesJsonParsed[sourceReg].hasOwnProperty('channels')) {
    alertInfo('抱歉频道不可用！');
    resetSourceReg();
  } else if (!sourcesJsonParsed[sourceReg].hasOwnProperty('play_url')) {
    for (let a = 0; a < sourcesJsonParsed[sourceReg].channels.length; a++) {
      if (sourcesJsonParsed[sourceReg].channels[a].chnl_id === programId) {
        hlsVideoUrl = sourcesJsonParsed[sourceReg].channels[a].url;
        resetSourceReg();
        videojsLoad();
      }
    }
  } else if (sourcesJsonParsed[sourceReg].auth_info_url && sourcesJsonParsed[sourceReg].auth_verify_url && localStorage.getItem(sourceReg+'_token')) {
    reqAuth();
  } else if (localStorage.getItem(sourceReg+'_token')) {
    hlsVideoUrl = sourcesJsonParsed[sourceReg].play_url+'?playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&playtoken=ABCDEFGHIGK&programid='+programId+'.m3u8';
    videojsLoad();
    updateAside();
  } else {
    alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源未注册或登录！',5);
    updateAside();
  }
}

function timeoutPromise(ms, promise) {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error("promise timeout"))
    }, ms);
    promise.then(
      (res) => {
        clearTimeout(timeoutId);
        resolve(res);
      },
      (err) => {
        clearTimeout(timeoutId);
        reject(err);
      }
    );
  })
}

function reqData(url, data = '', method = 'GET') {
  if (method === 'GET') {
    return fetch(url + data, {
      method: method,
      mode: "cors",
      cache: "no-cache",
      credentials: "omit",
      referrer: "",
    }).then(response => response.json());
  } else {
    return fetch(url, {
      method: method,
      mode: "cors",
      cache: "no-cache",
      credentials: "omit",
      referrer: "",
      body: JSON.stringify(data),
    }).then(response => response.json());
  }
}

function alertInfo(info,delay=3) {
  infoField.textContent = info;
  setTimeout(function run() {
    if (infoField.textContent === info) {
      infoField.textContent = '';
    }
  }, delay*1000);
}

function uniqueName() {
  if (sourcesJsonParsed[sourceReg].hasOwnProperty('unique_url')) {
    reqData(sourcesJsonParsed[sourceReg].unique_url,'?accounttype='+sourcesJsonParsed[sourceReg].acc_type_reg+'&username='+regAccField.value)
    .then(response => {
      if (response.ret !== 0) {
        alertInfo('用户名已存在,请重新输入！',3);
      }
    }).catch(err => console.log('发生错误:', err));
  }
}

function regImg() {
  if (sourcesJsonParsed[sourceReg].hasOwnProperty('img_url')) {
    let tokenUrl,imgUrl;
    tokenUrl = sourcesJsonParsed[sourceReg].token_url;
    imgUrl = sourcesJsonParsed[sourceReg].img_url;

    if (sourcesJsonParsed[sourceReg].hasOwnProperty('refresh_token_url')) {
      let deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
      deviceno = deviceno+md5(deviceno).substring(7, 8);
      timeoutPromise(3000,reqData(tokenUrl,{"role":"guest","deviceno":deviceno,"deviceType":"yuj"},'POST'))
      .then(response => {
        if (response.ret !== 0) {
          alertInfo('验证码请求错误！');
        } else {
          reqData(sourcesJsonParsed[sourceReg].refresh_token_url,{"accessToken":response.accessToken,"refreshToken":response.refreshToken},'POST')
          .then(response => {
            if (response.ret !== 0) {
              alertInfo('验证码请求错误！');
            } else {
              reqData(imgUrl,'?accesstoken='+response.accessToken)
              .then(response => {
                const newImage = document.createElement('img');
                newImage.src = response.image.replace('\\','/');
                regImgField.innerHTML = newImage.outerHTML;
                regImgIdField.value = response.picid;
              }).catch(err => console.log('发生错误:', err));
            }
          }).catch(err => console.log('发生错误:', err));
        }
      }).catch(err => {
        console.log('发生错误:', err);
        alertInfo('无法连接此直播源！', 10);
      });
    } else {
      timeoutPromise(3000,reqData(tokenUrl,{"usagescen":1},'POST'))
      .then(response => {
        if (response.ret !== 0) {
          alertInfo('验证码请求错误！');
        } else {
          reqData(imgUrl,'?accesstoken='+response.access_token)
          .then(response => {
            const newImage = document.createElement('img');
            newImage.src = response.image.replace('\\','/');
            regImgField.innerHTML = newImage.outerHTML;
            regImgIdField.value = response.picid;
          }).catch(err => console.log('发生错误:', err));
        }
      }).catch(err => {
        console.log('发生错误:', err);
        alertInfo('无法连接此直播源！', 10);
      });
    }
  }
}

function reqSms() {
  if (sourcesJsonParsed[sourceReg].hasOwnProperty('sms_url')) {
    let regAcc = regAccField.value;
    let regImgInput = regImgInputField.value;
    let regImgId = regImgIdField.value;
    let url;
    url = sourcesJsonParsed[sourceReg].sms_url;

    reqData(url,'?pincode='+regImgInput+'&picid='+regImgId+'&verifytype=3&account='+regAcc+'&accounttype=1')
    .then(response => {
      if (response.ret !== 0) {
        alertInfo('验证码或其它错误！请重新输入！');
      } else {
        alertInfo('短信已发送！',5);
      }
    }).catch(err => console.log('发生错误:', err));
  }
}

function reqReg() {
  let acc = regAccField.value;
  acc = acc.toString();
  let pwd = regPwdField.value;
  let smsCode = regSmsField.value;

  if (!sourcesJsonParsed[sourceReg].hasOwnProperty('img_url')) {
    reqData(sourcesJsonParsed[sourceReg].reg_url,'?username='+acc+'&iconid=1&pwd='+md5(pwd)+'&birthday=1970-1-1&type=1&accounttype='+sourcesJsonParsed[sourceReg].acc_type_reg)
    .then(response => {
      if (response.ret !== 0) {
        alertInfo(sourcesJsonParsed[sourceReg].desc + '直播源注册失败，请重试！');
      } else {
        formToggle.click();
        loginAccField.value = acc;
        loginPwdField.value = pwd;
        regAccField.value = '';
        regPwdField.value = '';
        regImgInputField.value = '';
        regSmsField.value = '';
        alertInfo('注册成功!');
        reqLogin();
      }
    }).catch(err => console.log('发生错误:', err));
  } else {
    reqData(sourcesJsonParsed[sourceReg].verify_url,'?verifycode='+smsCode+'&verifytype=3&username='+acc+'&account='+acc)
    .then(response => {
      if (response.ret === 0) {
        let user = {};
        user.account = acc;
        let deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
        user.deviceno = deviceno+md5(deviceno).substring(7, 8);
        user.devicetype = 'yuj';
        user.code = response.code;
        let timestamp = Date.now();
        user.signature = md5(acc+'|'+md5(pwd)+'|'+user.deviceno+'|'+user.devicetype+'|'+timestamp);
        user.birthday = '1970-1-1';
        user.username = acc;
        user.type = 1;
        user.timestamp = timestamp.toString();
        user.pwd = md5(pwd);
        user.accounttype = sourcesJsonParsed[sourceReg].acc_type_reg;

        reqData(sourcesJsonParsed[sourceReg].reg_url,user,'POST')
        .then(response => {
          if (response.ret === 0) {
            localStorage.setItem(sourceReg+'_deviceno', user.deviceno);
            formToggle.click();
            loginAccField.value = acc;
            loginPwdField.value = pwd;
            regAccField.value = '';
            regPwdField.value = '';
            regImgInputField.value = '';
            regSmsField.value = '';
            alertInfo('注册成功!');
            reqLogin();
          } else {
            alertInfo('注册失败,手机号已存在！', 10);
          }
        }).catch(err => console.log('发生错误:', err));
      } else {
        alertInfo('短信验证失败,请重试！');
      }
    }).catch(err => console.log('发生错误:', err));
  }
}

function reqLogin() {
  let acc = loginAccField.value;
  acc = acc.toString();
  let pwd = loginPwdField.value;
  let deviceno;
  if (localStorage.getItem(sourceReg+'_deviceno')) {
    deviceno = localStorage.getItem(sourceReg+'_deviceno');
  } else {
    deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
    deviceno = deviceno + md5(deviceno).substring(7, 8);
  }
  let devicetype = 3;
  let isforce = 1;

  if (!sourcesJsonParsed[sourceReg].hasOwnProperty('img_url')) {
    reqData(sourcesJsonParsed[sourceReg].login_url,'?deviceno='+deviceno+'&devicetype='+devicetype+'&accounttype='+sourcesJsonParsed[sourceReg].acc_type_login+'&accesstoken=(null)&account='+acc+'&pwd='+md5(pwd)+'&isforce='+isforce)
    .then(response => {
      if (response.ret === 0) {
        alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源登录成功！',5);
        localStorage.setItem(sourceReg+'_acc', acc);
        localStorage.setItem(sourceReg+'_pwd', pwd);
        localStorage.setItem(sourceReg+'_token', response.access_token);
        localStorage.setItem(sourceReg+'_deviceno', deviceno);
        initialize();
      } else {
        alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源登录失败！',10);
      }
    }).catch(err => console.log('发生错误:', err));
  } else {
    let user = {};
    user.account = acc;
    user.deviceno = deviceno;
    user.pwd = md5(pwd);
    user.devicetype = 'yuj';
    user.businessplatform = 1;
    let timestamp = Date.now();
    user.signature = md5(deviceno+'|'+user.devicetype+'|'+sourcesJsonParsed[sourceReg].acc_type_login+'|'+acc+"|"+timestamp);
    user.isforce = 1;
    user.extendinfo = sourcesJsonParsed[sourceReg].extend_info;
    if (sourcesJsonParsed[sourceReg].server_version) {
      user.serverVersion = sourcesJsonParsed[sourceReg].server_version;
    }
    user.timestamp = timestamp.toString();
    user.accounttype = sourcesJsonParsed[sourceReg].acc_type_login;

    timeoutPromise(3000,reqData(sourcesJsonParsed[sourceReg].login_url,user,'POST'))
    .then(response => {
      if (response.ret !== 0) {
        alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源登录失败！',10);
      } else {
        alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源登录成功！',5);
        localStorage.setItem(sourceReg+'_acc', acc);
        localStorage.setItem(sourceReg+'_pwd', pwd);
        localStorage.setItem(sourceReg+'_token', response.access_token);
        initialize();
      }
    }).catch(err => {
      console.log('登录发生错误:', err);
      alertInfo('无法连接'+sourcesJsonParsed[sourceReg].desc+'直播源!', 10);
    });
  }
}

function appendList(channel,appendSourceName,sourceLane) {
  const channelListItem = document.createElement('li');
  const channelListText = document.createTextNode(channel.chnl_name);
  if (localStorage.getItem('dark') === '1'){
    channelListItem.classList.add('white');
  }
  if (localStorage.getItem(appendSourceName+'_token') || jsonChannels.hasOwnProperty(appendSourceName)){
    channelListItem.classList.add('working');
  }
  channelListItem.setAttribute('data-value',channel.chnl_id);
  channelListItem.setAttribute('data-source',appendSourceName);
  channelListItem.appendChild(channelListText);
  if (channel.chnl_cat.indexOf('高清') === -1) {
    const channelSup = document.createElement('sub');
    channelSup.textContent = sourceLane;
    channelListItem.appendChild(channelSup);
  }
  switch (channel.chnl_cat) {
    case '高清电信':
      myList1.appendChild(channelListItem);
      break;
    case '高清联通':
      myList1a.appendChild(channelListItem);
      break;
    case '标清':
      myList2.appendChild(channelListItem);
      break;
    case '央视':
      myList3.appendChild(channelListItem);
      break;
    case '卫视':
      myList4.appendChild(channelListItem);
      break;
    case '地方':
      myList5.appendChild(channelListItem);
      break;
    case '专业':
      myList8.appendChild(channelListItem);
      break;
    case '港澳台':
      myList9.appendChild(channelListItem);
      break;
    default:
      break;
  }
}

function reqJson(json) {
  timeoutPromise(5000,reqData(json))
  .then(response => {
    if (response.ret === 0) {
      let newChannel={};
      jsonChannels[response.data[0].name] = {};
      for (let index = 0; index < response.data[0].channels.length; index++) {
        const channel = response.data[0].channels[index];
        jsonChannels[response.data[0].name][channel.chnl_id] = channel.url;
        newChannel.chnl_name = channel.chnl_name;
        newChannel.chnl_id = channel.chnl_id;
        newChannel.chnl_cat = channel.chnl_cat;
        appendList(newChannel,response.data[0].name,response.data[0].lane);
      }
    }
  }).catch(err => {
    console.log('发生错误:', err);
  });
}

function getToken(source) {
  return new Promise((resolve, reject) => {
    if (localStorage.getItem(source.name+'_token')) {
        resolve(localStorage.getItem(source.name+'_token'));
    } else {
      if (source.hasOwnProperty('refresh_token_url')) {
        let deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
        deviceno = deviceno+md5(deviceno).substring(7, 8);
        timeoutPromise(3000,reqData(source.token_url,{"role":"guest","deviceno":deviceno,"deviceType":"yuj"},'POST'))
        .then(response => {
          if (response.ret === 0) {
            reqData(source.refresh_token_url,{"accessToken":response.accessToken,"refreshToken":response.refreshToken},'POST')
            .then(response => {
              if (response.ret === 0) {
                resolve(response.accessToken);
              }
            }).catch(err => {reject(err);});
          }
        }).catch(err => {reject(err);});
      } else {
        timeoutPromise(3000,reqData(source.token_url,{"usagescen":1},'POST'))
        .then(response => {
          if (response.ret === 0) {
            resolve(response.access_token);
          }
        }).catch(err => {reject(err);});
      }
    }
  });
}

function reqChannels(source,token) {
  timeoutPromise(5000,reqData(source.list_url,'?pageidx=1&pagenum=500&accesstoken='+token))
  .then(response => {
    if (response.ret === 0) {
      let channelCats;
      let cats = {"001":"高清"+source.lane,"002":"标清","003":"央视","004":"卫视","005":"地方","008":"专业"};
      let omitArr = [];
      if (source.omit) {
        let omitSourceArr = source.omit.split(',');
        for (let index = 0; index < omitSourceArr.length; index++) {
          if (omitSourceArr[index].indexOf('-') !== -1) {
            let omitSubArr = omitSourceArr[index].split('-');
            for (let a = Number(omitSubArr[0]); a <= Number(omitSubArr[1]); a++) {
              omitArr.push(Number(a));
            }
          } else {
            omitArr.push(Number(omitSourceArr[index]));
          }
        }
      }
      for (let b = 0; b < response.chnl_list.length; b++) {
        const channel = response.chnl_list[b];
        if (source.omit && omitArr.indexOf(Number(channel.chnl_id.toString().slice(-3))) !== -1) {
          continue;
        }
        let newChannel={};
        channelCats = channel.sub_type.split('|');
        for (let c = 0; c < channelCats.length; c++) {
          let channelCat = channelCats[c].slice(-3);
          if (sourcesJsonParsed[source.name].hasOwnProperty('fix_cats') && sourcesJsonParsed[source.name].fix_cats.hasOwnProperty(channelCat)) {
            channelCat = sourcesJsonParsed[source.name].fix_cats[channelCat];
          }
          if (cats[channelCat] === undefined) {
            continue;
          }
          newChannel.chnl_name = channel.chnl_name;
          newChannel.chnl_id = channel.chnl_id;
          newChannel.chnl_cat = cats[channelCat];
          appendList(newChannel,source.name,source.lane);
        }
      }
    } else {
      alertInfo(sourcesJsonParsed[source.name].desc+'直播源错误！需重新注册或登录！',10);
      localStorage.removeItem(source.name+'_acc');
      localStorage.removeItem(source.name+'_pwd');
      localStorage.removeItem(source.name+'_token');
      localStorage.removeItem(source.name+'_deviceno');
    }
  }).catch(err => {
    alertInfo('无法连接'+sourcesJsonParsed[source.name].desc+'直播源！',10);
    console.log('发生错误:', err);
  });
}

function reqAuth() {
  timeoutPromise(3000,reqData(sourcesJsonParsed[sourceReg].auth_info_url,'?accesstoken='+localStorage.getItem(sourceReg+'_token')+'&programid='+programId+'&playtype=live&protocol=hls&verifycode='+localStorage.getItem(sourceReg+'_deviceno')))
  .then(response => {
    if (response.ret === 0) {
      let playToken = response.play_token;
      let authtoken = md5('ipanel123#%#&*(&(*#*&^*@#&*%()#*()$)#@&%(*@#()*%321ipanel'+response.auth_random_sn);
      timeoutPromise(3000,reqData(sourcesJsonParsed[sourceReg].auth_verify_url,'?programid='+programId+'&playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&verifycode='+localStorage.getItem(sourceReg+'_deviceno')+'&authtoken='+authtoken))
      .then(response => {
        if (response.ret === 0) {
          hlsVideoUrl = sourcesJsonParsed[sourceReg].play_url+'?playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&programid='+programId+'&playtoken='+playToken+'&verifycode='+localStorage.getItem(sourceReg+'_deviceno');
          videojsLoad();
        } else {
          alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源发生错误！',10);
        }
      }).catch(err => {
        alertInfo('无法连接'+sourcesJsonParsed[sourceReg].desc+'直播源！',10);
        console.log('发生错误:', err);
      });;
    } else {
      alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源错误！需重新注册或登录！',10);
      localStorage.removeItem(sourceReg+'_acc');
      localStorage.removeItem(sourceReg+'_pwd');
      localStorage.removeItem(sourceReg+'_token');
      localStorage.removeItem(sourceReg+'_deviceno');
    }
  }).catch(err => {
    alertInfo('无法连接'+sourcesJsonParsed[sourceReg].desc+'直播源！',10);
    console.log('发生错误:', err);
  });
  updateAside();
}

function parseJson(json) {
  let newJson = {};
  for (let index = 0; index < json.data.length; index++) {
    const element = json.data[index];
    if (element.play_url) {
      const sourcesListItem = document.createElement('li');
      sourcesListItem.textContent = element.desc;
      sourcesListItem.className = 'source_' + element.name;
      if (localStorage.getItem('dark') === '1'){
        sourcesListItem.classList.add('white');
      }
      sourcesField.appendChild(sourcesListItem);
    }

    let newIndex = element.name;
    newJson[newIndex] = element;
  }
  if (!sourcesField.firstChild) {
    sourcesField.textContent = '无';
  }
  sourcesJsonParsed = newJson;
}

function updateAside() {
  const selected = document.querySelector('.sourceReg');
  if(selected) selected.classList.remove('sourceReg');
  document.querySelector('.source_'+sourceReg).classList.add('sourceReg');
  if (!sourcesJsonParsed[sourceReg].hasOwnProperty('play_url')) {
    sourceReg = 'jscnwx';
    loginAccField.setAttribute('placeholder','用户名');
    regAccField.setAttribute('placeholder','用户名');
  } else if (!sourcesJsonParsed[sourceReg].hasOwnProperty('img_url')) {
    loginAccField.setAttribute('placeholder','用户名');
    regAccField.setAttribute('placeholder','用户名');
    regImgField.classList.toggle('hidden',true);
    regImgInputField.classList.toggle('hidden',true);
    regSmsField.classList.toggle('hidden',true);
  } else {
    loginAccField.setAttribute('placeholder','手机号');
    regAccField.setAttribute('placeholder','手机号');
    regImgField.classList.toggle('hidden',false);
    regImgInputField.classList.toggle('hidden',false);
    regSmsField.classList.toggle('hidden',false);
  }
  loginAccField.value = localStorage.getItem(sourceReg+'_acc');
  loginPwdField.value = localStorage.getItem(sourceReg+'_pwd');
}

function resetSourceReg() {
  sourceReg = 'jscnwx';
  programId = undefined;
  updateAside();
}

let sourcesJson,sourcesJsonParsed,jsonChannels={},hlsVideoUrl;
let sourceReg = 'jscnwx';
let programId;
let localJson = 'channels.json';
let remoteJson = 'http://hbo.epub.fun/channels.json';
const videoField = document.querySelector('.videoContainer');
const sourcesField = document.querySelector('.sources');
const loginForm = document.querySelector('.loginForm');
const loginAccField = document.querySelector('.loginAcc');
const loginPwdField = document.querySelector('.loginPwd');
const loginBtn = document.querySelector('.loginBtn');
const regForm = document.querySelector('.regForm');
const regAccField = document.querySelector('.regAcc');
const regPwdField = document.querySelector('.regPwd');
const regImgField = document.querySelector('.regImg');
const regImgInputField = document.querySelector('.regImgInput');
const regImgIdField = document.querySelector('.regImgId');
const regSmsField = document.querySelector('.regSms');
const regBtn = document.querySelector('.regBtn');
const infoField = document.querySelector('h4');
const formToggle = document.querySelector('.formToggle');
const channelsField = document.querySelector('.channels');
const categoriesField = document.querySelector('.categories');
const switchBtn = document.querySelector('.switch');
const myList1 = document.querySelector('.channels ul:nth-child(1)');
const myList1a = document.querySelector('.channels ul:nth-child(2)');
const myList2 = document.querySelector('.channels ul:nth-child(3)');
const myList3 = document.querySelector('.channels ul:nth-child(4)');
const myList4 = document.querySelector('.channels ul:nth-child(5)');
const myList5 = document.querySelector('.channels ul:nth-child(6)');
const myList8 = document.querySelector('.channels ul:nth-child(7)');
const myList9 = document.querySelector('.channels ul:nth-child(8)');

let liveui = true;
if (videojs.browser.IS_ANDROID || videojs.browser.IS_IOS) {
  liveui = false;
}

fetch(localJson).then(response => {
  let contentType;
  if(response.ok) {
    contentType = response.headers.get("content-type");
    if(contentType && contentType.includes("application/json")) {
      return response.json();
    }
  }
  fetch(remoteJson).then(response => {
    if(response.ok) {
      contentType = response.headers.get("content-type");
      if(contentType && contentType.includes("application/json")) {
        return response.json();
      }
    }
  }).then(json => {
    sourcesJson = json;
    parseJson(json);
    initialize();
  }).catch(err => {
    console.log('发生错误:', err.message);
  });
  throw new Error('本地频道不存在，尝试连接远程频道...');
}).then(json => {
  sourcesJson = json;
  parseJson(json);
  initialize();
}).catch(err => {
  console.log('发生错误:', err);
});

function initialize() {
  myList1.textContent = '';
  myList1.classList.add('myList1');
  myList1a.textContent = '';
  myList1a.classList.add('myList1a');
  myList1a.classList.add('hidden');
  myList2.textContent = '';
  myList2.classList.add('myList2');
  myList2.classList.add('hidden');
  myList3.textContent = '';
  myList3.classList.add('myList3');
  myList3.classList.add('hidden');
  myList4.textContent = '';
  myList4.classList.add('myList4');
  myList4.classList.add('hidden');
  myList5.textContent = '';
  myList5.classList.add('myList5');
  myList5.classList.add('hidden');
  myList8.textContent = '';
  myList8.classList.add('myList8');
  myList8.classList.add('hidden');
  myList9.textContent = '';
  myList9.classList.add('myList9');
  myList9.classList.add('hidden');
  for (let index = 0; index < sourcesJson.data.length; index++) {
    const source = sourcesJson.data[index];
    if (source.hasOwnProperty('json')) {
      reqJson(source.json);
    }
    if (source.hasOwnProperty('list_url')) {
      getToken(source).then(response => {reqChannels(source,response);})
      .catch(err => {console.log('发生错误:', err);});
    }
    if (source.hasOwnProperty('channels')) {
      for (let a = 0; a < source.channels.length; a++) {
        appendList(source.channels[a],source.name,source.lane);
      }
    }
  }

  if (localStorage.getItem(sourceReg+'_acc') && localStorage.getItem(sourceReg+'_pwd')){
    loginAccField.value = localStorage.getItem(sourceReg+'_acc');
    loginPwdField.value = localStorage.getItem(sourceReg+'_pwd');
  }

  updateAside();
  playVideo();
}

formToggle.addEventListener("click", function(e) {
  e.preventDefault();
  loginForm.classList.toggle('hidden');
  regForm.classList.toggle('hidden');
  if (formToggle.textContent === '注册') {
    formToggle.textContent = '登录';
  } else {
    formToggle.textContent = '注册';
  }
});

regAccField.addEventListener("change", uniqueName);
regAccField.addEventListener("change", regImg);
regImgField.addEventListener("click", regImg);
regImgInputField.addEventListener("change", reqSms);
regBtn.addEventListener("click", reqReg);
loginBtn.addEventListener("click", reqLogin);
sourcesField.addEventListener("click", switchSource);
categoriesField.addEventListener("click", switchCategory);
channelsField.addEventListener("click", switchChannel);

if (localStorage.getItem('dark') === '1'){
  switchBtn.click();
}