"use strict";
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
  elements.forEach(element => {
    element.classList.toggle(n)
  });
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
        toggleClass('a','white');
        toggleClass('body','bgBlack');
        toggleClass('input','bgBlack');
        toggleClass('footer','hidden');
        break;
      default:
        const selected = document.querySelector('.borderRed');
        if(selected) selected.classList.remove('borderRed');
        if (e.target.dataset.source) {
          sourceReg = e.target.dataset.source;
          programId = catValue;
          playVideo();
          const selected = document.querySelector('.selected');
          if(selected) selected.classList.remove('selected');
          e.target.classList.add('selected');
        } else {
          e.target.classList.add('borderRed');
          const mylist = document.querySelector('.'+catValue);
          let siblings = mylist.parentNode.childNodes;
          siblings.forEach(sibling => {
            if(sibling.nodeName === "UL") {
              sibling.classList.add('hidden');
            }
          });
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
  
  let contentType = hlsVideoUrl.indexOf('.flv') === -1 ? 'application/vnd.apple.mpegurl' : 'video/x-flv';
  const video = document.createElement('video');
  video.id = 'video';
  video.className = 'video-js';
  const noVideojs = document.createElement('p');
  noVideojs.className = 'vjs-no-js';
  const noVideojsText = document.createTextNode('需启用 JavaScript，或使用更新的浏览器');
  noVideojs.appendChild(noVideojsText);
  video.appendChild(noVideojs);
  videoField.appendChild(video);

  const player = videojs('video',{
    liveui: liveui,
    autoplay: 'true',
    preload: 'auto',
    playsinline: true,
    textTrackSettings: false,
    controls: true,
    fluid: true,
    responsive: true
  });

  player.src({
    src: hlsVideoUrl,
    type: contentType,
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
      alertInfo('频道不可用！',10);
      /*
      if (programId) {
        localStorage.removeItem(sourceReg+'_acc');
        localStorage.removeItem(sourceReg+'_pwd');
        localStorage.removeItem(sourceReg+'_token');
        localStorage.removeItem(sourceReg+'_verify_code');
      }
      */
    } else {
      alertInfo('无法连接直播源！',10);
    }
  });
}

function playVideo() {
  if(!programId) {
    let keyArr = Object.keys(sourcesJsonParsed);
    let index;
    while ((index = keyArr.pop()) !== undefined) {
      if (sourcesJsonParsed[index].hasOwnProperty('channels') && sourcesJsonParsed[index].channels[0] && sourcesJsonParsed[index].channels[0].hasOwnProperty('url')) {
        hlsVideoUrl = sourcesJsonParsed[index].channels[0].url;
        videojsLoad();
        if (sourcesJsonParsed[index].hasOwnProperty('overlay')) {
          videoOverlay(sourcesJsonParsed[index].overlay,sourcesJsonParsed[index].channels[0]);
        }
        showSchedule(sourcesJsonParsed[index].channels[0].schedule);
        resetSourceReg();
        break;
      }
    }
  } else if (jsonChannels[sourceReg]) {
    hlsVideoUrl = jsonChannels[sourceReg][programId]['url'];
    videojsLoad();
    if (jsonChannels[sourceReg].hasOwnProperty('overlay')) {
      videoOverlay(jsonChannels[sourceReg].overlay,jsonChannels[sourceReg][programId]);
    }
    showSchedule(jsonChannels[sourceReg][programId].schedule);
    resetSourceReg();
  } else if (!sourcesJsonParsed.hasOwnProperty(sourceReg) || !sourcesJsonParsed[sourceReg].hasOwnProperty('channels')) {
    deleteSchedule();
    alertInfo('抱歉频道不可用！');
    resetSourceReg();
  } else if (!sourcesJsonParsed[sourceReg].hasOwnProperty('play_url')) {
    sourcesJsonParsed[sourceReg].channels.forEach(channel => {
      if (channel.chnl_id === programId) {
        hlsVideoUrl = channel.url;
        videojsLoad();
        if (sourcesJsonParsed[sourceReg].hasOwnProperty('overlay')) {
          videoOverlay(sourcesJsonParsed[sourceReg].overlay,channel);
        }
        showSchedule(channel.schedule);
        resetSourceReg();
      }
    });
  } else if (localStorage.getItem(sourceReg+'_token')) {
    if (localStorage.getItem(sourceReg+'_verify_code')) {
      hlsVideoUrl = sourcesJsonParsed[sourceReg].play_url+'?playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&playtoken=ABCDEFGH&verifycode='+localStorage.getItem(sourceReg+'_verify_code')+'&programid='+programId+'.m3u8';
    } else {
      hlsVideoUrl = sourcesJsonParsed[sourceReg].play_url+'?playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&playtoken=ABCDEFGH&programid='+programId+'.m3u8';
    }
    videojsLoad();
    showSchedule();
    updateAside();
    /*if (sourcesJsonParsed[sourceReg].hasOwnProperty('auth_info_url') && sourcesJsonParsed[sourceReg].hasOwnProperty('auth_verify_url')) {
      reqAuth();
    }*/
  } else {
    deleteSchedule();
    alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源未注册或登录！',5);
    updateAside();
  }
}

function videoOverlay(sourceOverlay,channel) {
  let overlays = [],channelOverlay,channelOverlayArr = [];
  if (channel.hasOwnProperty('overlay') && channel.overlay.length > 0) {
    channelOverlay = channel.overlay;
    channelOverlayArr = channelOverlay.split(',');
  }
  sourceOverlay.forEach((sourceItem,sourceIndex) => {
    let overlayInfo = [];
    if (sourceItem.hasOwnProperty('force') && sourceItem.force === 1) {
      if (sourceItem.hasOwnProperty('switch') && sourceItem.switch === 'on') {
        overlays.push({class:'overlay'+sourceIndex.toString(),content:'',align:'center',start:'ready'});
        overlayInfo.push(sourceItem.height,sourceItem.width,sourceItem.margin_left,sourceItem.margin_top,sourceItem.height_fullscreen,sourceItem.width_fullscreen,sourceItem.margin_left_fullscreen,sourceItem.margin_top_fullscreen);
        overlaysInfo[sourceIndex] = overlayInfo;
      }
    } else if (channelOverlayArr.length > sourceIndex) {
      let channelOverlayIndex = channelOverlayArr[sourceIndex];
      if ((channelOverlayIndex === 'on' && sourceItem.reverse === 0) || (channelOverlayIndex === 'off' && sourceItem.reverse === 1)) {
        overlays.push({class:'overlay'+sourceIndex.toString(),content:'',align:'center',start:'ready'});
        overlayInfo.push(sourceItem.height,sourceItem.width,sourceItem.margin_left,sourceItem.margin_top,sourceItem.height_fullscreen,sourceItem.width_fullscreen,sourceItem.margin_left_fullscreen,sourceItem.margin_top_fullscreen);
        overlaysInfo[sourceIndex] = overlayInfo;
      } else if (channelOverlayIndex.indexOf(':') !== -1) {
        let channelOverlayIndexArr = channelOverlayIndex.split(':');
        if ((sourceItem.reverse === 0 && channelOverlayIndexArr[0] === 'on') || (sourceItem.reverse === 1 && overlayArr[0] === 'off')) {
          overlays.push({class:'overlay'+sourceIndex.toString(),content:'',align:'center',start:'ready'});
          channelOverlayIndexArr.shift();
          overlaysInfo[sourceIndex] = channelOverlayIndexArr;
        }
      }
    }
  });

  if (overlays.length > 0) {
    videojs('video').overlay({
      debug: false,
      overlays: overlays
    });
    for (let index = 0; index < overlays.length; index++) {
      const info = overlaysInfo[index];
      const overlayIndex = document.querySelector('.overlay'+index);
      overlayIndex.setAttribute('style', 'height:' + info[0] +'%; width: ' + info[1] + '%; margin-left: ' + info[2] + '%; margin-top: ' + info[3] + '%;');
    }
  }
}

function setOverlayFullscreen() {
  let width = window.screen.width * window.devicePixelRatio;
  let height = window.screen.height * window.devicePixelRatio;
  let videoWidth,videoHeight,newWidth,newHeight,marginLeft,marginTop;
  if (width > height && width / height !== 1.6) {
    videoHeight = height;
    videoWidth = videoHeight * 16 / 9;
  } else {
    videoWidth = width;
    videoHeight = videoWidth * 9 / 16;
  }

  for (let index = 0; index < Object.keys(overlaysInfo).length; index++) {
    const info = overlaysInfo[index];
    const overlayIndex = document.querySelector('.overlay'+index);
    if (document.fullscreenElement) {
      newHeight = Math.floor(videoHeight * info[4] / 100 / window.devicePixelRatio);
      newWidth = Math.floor(videoWidth * info[5] / 100 / window.devicePixelRatio);
      marginLeft = Math.floor(videoWidth * info[6] / 100 / window.devicePixelRatio);
      marginTop = Math.floor(videoHeight * info[7] / 100 / window.devicePixelRatio);

      overlayIndex.setAttribute('style', 'width:' + newWidth +'px; height: ' + newHeight + 'px; margin-left: ' + marginLeft + 'px; margin-top: ' + marginTop + 'px;');
    } else {
      overlayIndex.setAttribute('style', 'height:' + info[0] +'%; width: ' + info[1] + '%; margin-left: ' + info[2] + '%; margin-top: ' + info[3] + '%;');
    }
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
    }).then(response => {
      return response.json();
    }).catch(err => {
      console.log('发生错误:', err.message);
    });
  } else {
    return fetch(url, {
      method: method,
      mode: "cors",
      cache: "no-cache",
      credentials: "omit",
      referrer: "",
      body: JSON.stringify(data),
    }).then(response => {
      return response.json();
    }).catch(err => {
      console.log('发生错误:', err.message);
    });
  }
}

function alertInfo(text,delay=3) {
  alertField.textContent = text;
  setTimeout(function() {
    if (alertField.textContent === text) {
      alertField.textContent = '';
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
    });
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
              });
            }
          });
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
          });
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
    });
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
        alertInfo(sourcesJsonParsed[sourceReg].desc + '直播源注册失败，请重试！用户名不能是中文！');
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
    });
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
        });
      } else {
        alertInfo('短信验证失败,请重试！');
      }
    });
  }
}

function reqLogin() {
  let acc = loginAccField.value;
  acc = acc.toString();
  let pwd = loginPwdField.value;
  let deviceno;
  deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
  deviceno = deviceno + md5(deviceno).substring(7, 8);
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
        localStorage.setItem(sourceReg+'_verify_code', response.device_id);
        initialize();
      } else {
        alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源登录失败！',10);
      }
    });
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
        localStorage.setItem(sourceReg+'_verify_code', response.device_id);
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
      if (response.data[0].hasOwnProperty('overlay')) {
        jsonChannels[response.data[0].name]['overlay'] = response.data[0].overlay;
      }
      response.data[0].channels.forEach(channel => {
        jsonChannels[response.data[0].name][channel.chnl_id] = {};
        jsonChannels[response.data[0].name][channel.chnl_id]['url'] = channel.url;
        if (channel.hasOwnProperty('overlay')) {
          jsonChannels[response.data[0].name][channel.chnl_id]['overlay'] = channel.overlay;
        }
        if (channel.hasOwnProperty('schedule')) {
          jsonChannels[response.data[0].name][channel.chnl_id]['schedule'] = channel.schedule;
        }
        newChannel.chnl_name = channel.chnl_name;
        newChannel.chnl_id = channel.chnl_id;
        newChannel.chnl_cat = channel.chnl_cat;
        appendList(newChannel,response.data[0].name,response.data[0].lane);
      });
    }
  });
}

function getToken(source) {
  return new Promise((resolve, reject) => {
    if (source.hasOwnProperty('access_token')) {
      let deviceno;
      deviceno = makeStr(8)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(4)+"-"+makeStr(12);
      deviceno = deviceno + md5(deviceno).substring(7, 8);

      timeoutPromise(3000,reqData(source.login_url,'?deviceno='+deviceno+'&devicetype=3&accounttype=2&accesstoken=(null)&account='+source.access_token.substring(32)+'&pwd='+source.access_token.substring(0, 32)+'&isforce=1&businessplatform=1'))
      .then(response => {
        if (response.access_token) {
          localStorage.setItem(source.name+'_token', response.access_token);
          localStorage.setItem(source.name+'_verify_code', response.device_id);
          resolve(response.access_token);
        }
      }).catch(err => {reject(err);});
    } else if (localStorage.getItem(source.name+'_token')) {
      resolve(localStorage.getItem(source.name+'_token'));
    } else if (source.hasOwnProperty('refresh_token_url')) {
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
        omitSourceArr.forEach(omitSource => {
          if (omitSource.indexOf('-') !== -1) {
            let omitSubArr = omitSource.split('-');
            for (let a = Number(omitSubArr[0]); a <= Number(omitSubArr[1]); a++) {
              omitArr.push(Number(a));
            }
          } else {
            omitArr.push(Number(omitSource));
          }
        });
      }
      response.chnl_list.forEach(channel => {
        if (source.omit && omitArr.indexOf(Number(channel.chnl_id.toString().slice(-3))) !== -1) {
          return;
        }
        if (channel.sub_type.length === 0) {
          if (channel.chnl_name.indexOf('高清') !== -1) {
            channel.sub_type = '001';
          } else {
            channel.sub_type = '002';
          }
          if (channel.chnl_name.toUpperCase().indexOf('CCTV') !== -1) {
            channel.sub_type = channel.sub_type + '|003';
          }
          if (channel.chnl_name.indexOf('卫视') !== -1) {
            channel.sub_type = channel.sub_type + '|004';
          }
        }
        let newChannel={};
        channelCats = channel.sub_type.split('|');
        channelCats.forEach(channelCat => {
          channelCat = channelCat.slice(-3);
          if (sourcesJsonParsed[source.name].hasOwnProperty('fix_cats') && sourcesJsonParsed[source.name].fix_cats.hasOwnProperty(channelCat)) {
            channelCat = sourcesJsonParsed[source.name].fix_cats[channelCat];
          }
          if (cats[channelCat] === undefined) {
            return;
          }
          newChannel.chnl_name = channel.chnl_name;
          newChannel.chnl_id = channel.chnl_id;
          newChannel.chnl_cat = cats[channelCat];
          appendList(newChannel,source.name,source.lane);
        });
      });
    } else {
      alertInfo(sourcesJsonParsed[source.name].desc+'直播源错误！需重新注册或登录！',10);
      localStorage.removeItem(source.name+'_acc');
      localStorage.removeItem(source.name+'_pwd');
      localStorage.removeItem(source.name+'_token');
    }
  }).catch(err => {
    alertInfo('无法连接'+sourcesJsonParsed[source.name].desc+'直播源！',10);
    console.log('发生错误:', err);
  });
}

function reqAuth() {
  timeoutPromise(3000,reqData(sourcesJsonParsed[sourceReg].auth_info_url,'?accesstoken='+localStorage.getItem(sourceReg+'_token')+'&programid='+programId+'&playtype=live&protocol=hls&verifycode='+localStorage.getItem(sourceReg+'_verify_code')))
  .then(response => {
    if (response.ret === 0) {
      let authtoken = md5('ipanel123#%#&*(&(*#*&^*@#&*%()#*()$)#@&%(*@#()*%321ipanel'+response.auth_random_sn);
      timeoutPromise(3000,reqData(sourcesJsonParsed[sourceReg].auth_verify_url,'?programid='+programId+'&playtype=live&protocol=hls&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&verifycode='+localStorage.getItem(sourceReg+'_verify_code')+'&authtoken='+authtoken))
      .then(response => {
        if (response.ret !== 0) {
          alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源发生错误！',10);
        }
      }).catch(err => {
        alertInfo('无法连接'+sourcesJsonParsed[sourceReg].desc+'直播源！',10);
        console.log('发生错误:', err);
      });
    } else {
      alertInfo(sourcesJsonParsed[sourceReg].desc+'直播源错误！需重新注册或登录！',10);
      localStorage.removeItem(sourceReg+'_acc');
      localStorage.removeItem(sourceReg+'_pwd');
      localStorage.removeItem(sourceReg+'_token');
      localStorage.removeItem(sourceReg+'_verify_code');
    }
  }).catch(err => {
    alertInfo('无法连接'+sourcesJsonParsed[sourceReg].desc+'直播源！',10);
    console.log('发生错误:', err);
  });
}

function parseJson(json) {
  let newJson = {};
  json.data.forEach(element => {
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
  });

  if (!sourcesField.firstChild) {
    sourcesField.textContent = '无';
  }
  sourcesJsonParsed = newJson;
}

function updateAside() {
  const selected = document.querySelector('.sourceReg');
  if(selected) selected.classList.remove('sourceReg');
  const foundSource = document.querySelector('.source_'+sourceReg);
  if(foundSource) {
    foundSource.classList.add('sourceReg');
    if (sourcesJsonParsed[sourceReg].hasOwnProperty('access_token')) {
      fieldsetLoginForm.setAttribute("disabled","disabled");
      fieldsetRegForm.setAttribute("disabled","disabled");
      formToggle.disabled = true;
      return;
    } else if (!sourcesJsonParsed[sourceReg].hasOwnProperty('play_url')) {
      sourceReg = sourceRegDefault;
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
    fieldsetLoginForm.removeAttribute("disabled");
    fieldsetRegForm.removeAttribute("disabled");
    formToggle.disabled = false;
    loginAccField.value = localStorage.getItem(sourceReg+'_acc');
    loginPwdField.value = localStorage.getItem(sourceReg+'_pwd');
  }
}

function resetSourceReg() {
  sourceReg = sourceRegDefault;
  programId = undefined;
  updateAside();
}

function showSchedule(chnl) {
  deleteSchedule();

  if (!chnl) {
    if (!sourcesJsonParsed[sourceReg].hasOwnProperty('schedule_url')) {
      return;
    } else if (schedules[sourceReg] && schedules[sourceReg][programId]) {
      insertSchedule(sourceReg,programId);
    } else {
      let starttime = new Date();
      starttime = starttime.setHours(0,0,0,0) / 1000;
      let endtime = starttime + 86400;
      let chnlSource = sourceReg;
      let chnlId = programId;
      reqData(sourcesJsonParsed[chnlSource].schedule_url,'?accesstoken='+localStorage.getItem(sourceReg+'_token')+'&repeat=1&starttime='+starttime+'&endtime='+endtime+'&chnlid='+chnlId+'&pagenum=500&pageidx=1')
      .then(response => {
        if (!schedules.hasOwnProperty(chnlSource)) {
          schedules[chnlSource] = {};
        }
        schedules[chnlSource][chnlId] = [];
        for (let index = 0; index < response.total; index++) {
          let newEvent = {},newEventTime;
          const event = response.event_list[index];
          newEvent.event_id = event.event_id;
          newEvent.title = event.event_name;
          newEventTime = new Date(event.start_time * 1000);
          newEventTime = newEventTime.toLocaleString('en-US', { hour: 'numeric', minute: 'numeric', hour12: true });
          newEvent.time = newEventTime.replace(' ','');
          newEvent.sys_time = event.start_time.toString();
          schedules[chnlSource][chnlId].push(newEvent);
        }
        if (schedules[chnlSource][chnlId].length > 0) {
          insertSchedule(chnlSource,chnlId);
        }
      });
    }
  } else if (Object.keys(schedules).length === 0 && schedules.constructor === Object) {
    reqData(scheduleJson)
    .then(response => {
      schedules = response;
      insertSchedule(chnl);
    });
  } else {
    insertSchedule(chnl);
  }
}

function insertSchedule(chnl,chnlId) {
  if (!schedules.hasOwnProperty(chnl)) {
    sliderField.classList.add('hidden');
    return;
  }

  let chnlSchedules;

  if (chnlId) {
    if (!schedules[chnl].hasOwnProperty(chnlId) || schedules[chnl][chnlId].length === 0) {
      sliderField.classList.add('hidden');
      return;
    }
    chnlSchedules = schedules[chnl][chnlId];
  }
  else if (schedules[chnl].length === 0) {
    sliderField.classList.add('hidden');
    return;
  } else {
    chnlSchedules = schedules[chnl];
  }

  let scheduleTime = 1000000000,indexTime,slideIndex = 0;
  let dateNow = Date.now();

  for (let index = 0; index < chnlSchedules.length; index++) {
    const schedule = chnlSchedules[index];
    const scheduleListItem = document.createElement('li');
    const scheduleListText = document.createTextNode(schedule.time + ' ' + schedule.title);
    scheduleListItem.classList.add('js_slide');
    if (schedule.hasOwnProperty('id')) {
      scheduleListItem.setAttribute('data-id', schedule.id);
      scheduleListItem.setAttribute('data-channel', chnl);
    }
    if (schedule.hasOwnProperty('event_id')) {
      scheduleListItem.setAttribute('data-eventid', schedule.event_id);
    }
    scheduleListItem.appendChild(scheduleListText);
    scheduleField.appendChild(scheduleListItem);
    indexTime = schedule.sys_time * 1000;
    if (indexTime < dateNow && indexTime > scheduleTime) {
      scheduleTime = indexTime;
      slideIndex = index;
    }
  }

  sliderField.classList.remove('hidden');

  lory(sliderField, {
    initialIndex: slideIndex,
    rewind: true
  });
}

function deleteSchedule() {
  sliderField.classList.add('hidden');
  while (scheduleField.firstChild) {
    scheduleField.removeChild(scheduleField.firstChild);
  }
}

function playbackOrUpcoming(e) {
  if(e.target && e.target.nodeName === "LI") {
    if (e.target.hasAttribute('data-eventid')) {
      let eventId = e.target.dataset.eventid;
      reqData(sourcesJsonParsed[sourceReg].event_info_url,'?accesstoken='+localStorage.getItem(sourceReg+'_token')+'&eventid='+eventId)
      .then(response => {
        if (response.ret === 0) {
          let idx = response.event_idx;
          let startTime = response.start_time;
          let endTime = response.end_time;
          let playToken = response.play_token;
          let playbackUrl = response.demand_url[0];

          if (playbackUrl) {
            let eventStartTime = new Date(startTime * 1000);
            let eventStartTimeHours = eventStartTime.getHours();
            if (eventStartTimeHours < 10) {
              eventStartTimeHours = '0' + eventStartTimeHours;
            }
            let eventStartTimeMinutes = eventStartTime.getMinutes();
            if (eventStartTimeMinutes < 10) {
              eventStartTimeMinutes = '0' + eventStartTimeMinutes;
            }
            let eventStartTimeMilliseconds = eventStartTime.getMilliseconds();
            if (eventStartTimeMilliseconds < 10) {
              eventStartTimeMilliseconds = '0' + eventStartTimeMilliseconds;
            }
            startTime = idx + eventStartTimeHours + eventStartTimeMinutes + eventStartTimeMilliseconds;
  
            let eventEndTime = new Date(endTime * 1000);
            let eventEndTimeHours = eventEndTime.getHours();
            if (eventEndTimeHours < 10) {
              eventEndTimeHours = '0' + eventEndTimeHours;
            }
            let eventEndTimeMinutes = eventEndTime.getMinutes();
            if (eventEndTimeMinutes < 10) {
              eventEndTimeMinutes = '0' + eventEndTimeMinutes;
            }
            let eventEndTimeMilliseconds = eventEndTime.getMilliseconds();
            if (eventEndTimeMilliseconds < 10) {
              eventEndTimeMilliseconds = '0' + eventEndTimeMilliseconds;
            }
            endTime = idx + eventEndTimeHours + eventEndTimeMinutes + eventEndTimeMilliseconds;
            if (localStorage.getItem(sourceReg+'_verify_code')) {
              hlsVideoUrl = playbackUrl+'?playtype=lookback&protocol=hls&starttime='+startTime+'&endtime='+endTime+'&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&playtoken='+playToken+'&verifycode='+localStorage.getItem(sourceReg+'_verify_code')+'&programid='+eventId+'.m3u8';
            } else {
              hlsVideoUrl = playbackUrl+'?playtype=lookback&protocol=hls&starttime='+startTime+'&endtime='+endTime+'&accesstoken='+localStorage.getItem(sourceReg+'_token')+'&playtoken='+playToken+'&programid='+eventId+'.m3u8';
            }
            videojsLoad();
          } else {
            alertInfo('录像还未准备好！', 10);
          }
        }
      })
    } else if (e.target.hasAttribute('data-id')) {
      let showId =  e.target.dataset.id;
      let channel = e.target.dataset.channel;
      let hboLink;
      if (channel === "hbo") {
        hboLink = 'https://hboasia.com/HBO/zh-cn/ajax/home_schedule_upcoming_showtimes?channel=' + channel + '&feed=cn&id=' + showId;
      } else {
        hboLink = 'https://hboasia.com/HBO/zh-tw/ajax/home_schedule_upcoming_showtimes?channel=' + channel + '&feed=satellite&id=' + showId;
      }
      reqData(hboLink)
      .then(response => {
        let dateNow = Date.now();
        const upComingList = document.createElement('ul');
        upComingList.setAttribute('data-id', dateNow);
        const upComingListTitle = document.createTextNode('即將播出:');
        for (let index = 0; index < response.length; index++) {
          const schedule = response[index];
          if (schedule.id) {
            const upComingListItem = document.createElement('li');
            const upComingListText = document.createTextNode(schedule.time);
            upComingListItem.appendChild(upComingListText);
            upComingList.appendChild(upComingListItem);
          }
        }
        if (!upComingList.firstChild) {
          const upComingListItem = document.createElement('li');
          const upComingListText = document.createTextNode('无');
          upComingListItem.appendChild(upComingListText);
          upComingList.appendChild(upComingListItem);
        }
        while (upComingField.firstChild) {
          upComingField.removeChild(upComingField.firstChild);
        }
        upComingField.appendChild(upComingListTitle);
        upComingField.appendChild(upComingList);
        setTimeout(function() {
          if (upComingField.firstChild && upComingField.firstChild.nextSibling.dataset.id === dateNow.toString()) {
            while (upComingField.firstChild) {
              upComingField.removeChild(upComingField.firstChild);
            }
          }
        }, 10000);
      });
    }
  }
}

let programId,sourcesJson,sourcesJsonParsed,jsonChannels = {},hlsVideoUrl,schedules = {},overlaysInfo = {};
let sourceReg = 'hrtn',sourceRegDefault = 'hrtn';
let localJson = 'channels.json';
let remoteJson = 'http://hbo.epub.fun/channels.json';
let scheduleJson = 'http://hbo.epub.fun/schedule.json';
const videoField = document.querySelector('.videoContainer');
const sourcesField = document.querySelector('.sources');
const fieldsetLoginForm = document.querySelector('.loginForm fieldset');
const loginForm = document.querySelector('.loginForm');
const loginAccField = document.querySelector('.loginAcc');
const loginPwdField = document.querySelector('.loginPwd');
const loginBtn = document.querySelector('.loginBtn');
const fieldsetRegForm = document.querySelector('.regForm fieldset');
const regForm = document.querySelector('.regForm');
const regAccField = document.querySelector('.regAcc');
const regPwdField = document.querySelector('.regPwd');
const regImgField = document.querySelector('.regImg');
const regImgInputField = document.querySelector('.regImgInput');
const regImgIdField = document.querySelector('.regImgId');
const regSmsField = document.querySelector('.regSms');
const regBtn = document.querySelector('.regBtn');
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
const alertField = document.querySelector('.alert');
const upComingField = document.querySelector('.upComing');
const sliderField = document.querySelector('.js_slider');
const scheduleField = document.querySelector('.slides');

let liveui = true;
if (videojs.browser.IS_ANDROID || videojs.browser.IS_IOS) {
  liveui = false;
}

reqData(localJson).then(response => {
  sourcesJson = response;
  parseJson(response);
  initialize();
}).catch(err => {
  console.log('发生错误:', err);
  reqData(remoteJson).then(response => {
    sourcesJson = response;
    parseJson(response);
    initialize();
  });
  throw new Error('本地频道不存在，尝试连接远程频道...');
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

  sourcesJson.data.forEach(source => {
    if (source.hasOwnProperty('json')) {
      reqJson(source.json);
    }
    if (source.hasOwnProperty('list_url')) {
      getToken(source).then(response => {reqChannels(source,response);})
      .catch(err => {console.log('发生错误:', err);});
    }
    if (source.hasOwnProperty('channels')) {
      source.channels.forEach(channel => {
        if (channel.hasOwnProperty('chnl_cat')) {
          appendList(channel,source.name,source.lane);
        }
      });
    }
  });

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
scheduleField.addEventListener("click", playbackOrUpcoming);
channelsField.addEventListener("click", switchChannel);
document.addEventListener("fullscreenchange", setOverlayFullscreen);
document.addEventListener("webkitfullscreenchange", setOverlayFullscreen);
document.addEventListener("mozfullscreenchange", setOverlayFullscreen);
document.addEventListener("msfullscreenchange", setOverlayFullscreen);
window.addEventListener("orientationchange", setOverlayFullscreen);

if (localStorage.getItem('dark') === '1'){
  switchBtn.click();
}