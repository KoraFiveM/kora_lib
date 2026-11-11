function Yn(t,e){for(var n=0;n<e.length;n++){const r=e[n];if(typeof r!="string"&&!Array.isArray(r)){for(const a in r)if(a!=="default"&&!(a in t)){const o=Object.getOwnPropertyDescriptor(r,a);o&&Object.defineProperty(t,a,o.get?o:{enumerable:!0,get:()=>r[a]})}}}return Object.freeze(Object.defineProperty(t,Symbol.toStringTag,{value:"Module"}))}var Fo=typeof globalThis<"u"?globalThis:typeof window<"u"?window:typeof global<"u"?global:typeof self<"u"?self:{};function Ve(t){return t&&t.__esModule&&Object.prototype.hasOwnProperty.call(t,"default")?t.default:t}var Ge={exports:{}},h={};/**
 * @license React
 * react.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */var nt=Symbol.for("react.element"),Hn=Symbol.for("react.portal"),Vn=Symbol.for("react.fragment"),Gn=Symbol.for("react.strict_mode"),Bn=Symbol.for("react.profiler"),Xn=Symbol.for("react.provider"),qn=Symbol.for("react.context"),Kn=Symbol.for("react.forward_ref"),Qn=Symbol.for("react.suspense"),Jn=Symbol.for("react.memo"),Zn=Symbol.for("react.lazy"),ue=Symbol.iterator;function tr(t){return t===null||typeof t!="object"?null:(t=ue&&t[ue]||t["@@iterator"],typeof t=="function"?t:null)}var Be={isMounted:function(){return!1},enqueueForceUpdate:function(){},enqueueReplaceState:function(){},enqueueSetState:function(){}},Xe=Object.assign,qe={};function q(t,e,n){this.props=t,this.context=e,this.refs=qe,this.updater=n||Be}q.prototype.isReactComponent={};q.prototype.setState=function(t,e){if(typeof t!="object"&&typeof t!="function"&&t!=null)throw Error("setState(...): takes an object of state variables to update or a function which returns an object of state variables.");this.updater.enqueueSetState(this,t,e,"setState")};q.prototype.forceUpdate=function(t){this.updater.enqueueForceUpdate(this,t,"forceUpdate")};function Ke(){}Ke.prototype=q.prototype;function Xt(t,e,n){this.props=t,this.context=e,this.refs=qe,this.updater=n||Be}var qt=Xt.prototype=new Ke;qt.constructor=Xt;Xe(qt,q.prototype);qt.isPureReactComponent=!0;var de=Array.isArray,Qe=Object.prototype.hasOwnProperty,Kt={current:null},Je={key:!0,ref:!0,__self:!0,__source:!0};function Ze(t,e,n){var r,a={},o=null,i=null;if(e!=null)for(r in e.ref!==void 0&&(i=e.ref),e.key!==void 0&&(o=""+e.key),e)Qe.call(e,r)&&!Je.hasOwnProperty(r)&&(a[r]=e[r]);var s=arguments.length-2;if(s===1)a.children=n;else if(1<s){for(var f=Array(s),c=0;c<s;c++)f[c]=arguments[c+2];a.children=f}if(t&&t.defaultProps)for(r in s=t.defaultProps,s)a[r]===void 0&&(a[r]=s[r]);return{$$typeof:nt,type:t,key:o,ref:i,props:a,_owner:Kt.current}}function er(t,e){return{$$typeof:nt,type:t.type,key:e,ref:t.ref,props:t.props,_owner:t._owner}}function Qt(t){return typeof t=="object"&&t!==null&&t.$$typeof===nt}function nr(t){var e={"=":"=0",":":"=2"};return"$"+t.replace(/[=:]/g,function(n){return e[n]})}var me=/\/+/g;function At(t,e){return typeof t=="object"&&t!==null&&t.key!=null?nr(""+t.key):e.toString(36)}function ft(t,e,n,r,a){var o=typeof t;(o==="undefined"||o==="boolean")&&(t=null);var i=!1;if(t===null)i=!0;else switch(o){case"string":case"number":i=!0;break;case"object":switch(t.$$typeof){case nt:case Hn:i=!0}}if(i)return i=t,a=a(i),t=r===""?"."+At(i,0):r,de(a)?(n="",t!=null&&(n=t.replace(me,"$&/")+"/"),ft(a,e,n,"",function(c){return c})):a!=null&&(Qt(a)&&(a=er(a,n+(!a.key||i&&i.key===a.key?"":(""+a.key).replace(me,"$&/")+"/")+t)),e.push(a)),1;if(i=0,r=r===""?".":r+":",de(t))for(var s=0;s<t.length;s++){o=t[s];var f=r+At(o,s);i+=ft(o,e,n,f,a)}else if(f=tr(t),typeof f=="function")for(t=f.call(t),s=0;!(o=t.next()).done;)o=o.value,f=r+At(o,s++),i+=ft(o,e,n,f,a);else if(o==="object")throw e=String(t),Error("Objects are not valid as a React child (found: "+(e==="[object Object]"?"object with keys {"+Object.keys(t).join(", ")+"}":e)+"). If you meant to render a collection of children, use an array instead.");return i}function it(t,e,n){if(t==null)return t;var r=[],a=0;return ft(t,r,"","",function(o){return e.call(n,o,a++)}),r}function rr(t){if(t._status===-1){var e=t._result;e=e(),e.then(function(n){(t._status===0||t._status===-1)&&(t._status=1,t._result=n)},function(n){(t._status===0||t._status===-1)&&(t._status=2,t._result=n)}),t._status===-1&&(t._status=0,t._result=e)}if(t._status===1)return t._result.default;throw t._result}var P={current:null},ct={transition:null},ar={ReactCurrentDispatcher:P,ReactCurrentBatchConfig:ct,ReactCurrentOwner:Kt};function tn(){throw Error("act(...) is not supported in production builds of React.")}h.Children={map:it,forEach:function(t,e,n){it(t,function(){e.apply(this,arguments)},n)},count:function(t){var e=0;return it(t,function(){e++}),e},toArray:function(t){return it(t,function(e){return e})||[]},only:function(t){if(!Qt(t))throw Error("React.Children.only expected to receive a single React element child.");return t}};h.Component=q;h.Fragment=Vn;h.Profiler=Bn;h.PureComponent=Xt;h.StrictMode=Gn;h.Suspense=Qn;h.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED=ar;h.act=tn;h.cloneElement=function(t,e,n){if(t==null)throw Error("React.cloneElement(...): The argument must be a React element, but you passed "+t+".");var r=Xe({},t.props),a=t.key,o=t.ref,i=t._owner;if(e!=null){if(e.ref!==void 0&&(o=e.ref,i=Kt.current),e.key!==void 0&&(a=""+e.key),t.type&&t.type.defaultProps)var s=t.type.defaultProps;for(f in e)Qe.call(e,f)&&!Je.hasOwnProperty(f)&&(r[f]=e[f]===void 0&&s!==void 0?s[f]:e[f])}var f=arguments.length-2;if(f===1)r.children=n;else if(1<f){s=Array(f);for(var c=0;c<f;c++)s[c]=arguments[c+2];r.children=s}return{$$typeof:nt,type:t.type,key:a,ref:o,props:r,_owner:i}};h.createContext=function(t){return t={$$typeof:qn,_currentValue:t,_currentValue2:t,_threadCount:0,Provider:null,Consumer:null,_defaultValue:null,_globalName:null},t.Provider={$$typeof:Xn,_context:t},t.Consumer=t};h.createElement=Ze;h.createFactory=function(t){var e=Ze.bind(null,t);return e.type=t,e};h.createRef=function(){return{current:null}};h.forwardRef=function(t){return{$$typeof:Kn,render:t}};h.isValidElement=Qt;h.lazy=function(t){return{$$typeof:Zn,_payload:{_status:-1,_result:t},_init:rr}};h.memo=function(t,e){return{$$typeof:Jn,type:t,compare:e===void 0?null:e}};h.startTransition=function(t){var e=ct.transition;ct.transition={};try{t()}finally{ct.transition=e}};h.unstable_act=tn;h.useCallback=function(t,e){return P.current.useCallback(t,e)};h.useContext=function(t){return P.current.useContext(t)};h.useDebugValue=function(){};h.useDeferredValue=function(t){return P.current.useDeferredValue(t)};h.useEffect=function(t,e){return P.current.useEffect(t,e)};h.useId=function(){return P.current.useId()};h.useImperativeHandle=function(t,e,n){return P.current.useImperativeHandle(t,e,n)};h.useInsertionEffect=function(t,e){return P.current.useInsertionEffect(t,e)};h.useLayoutEffect=function(t,e){return P.current.useLayoutEffect(t,e)};h.useMemo=function(t,e){return P.current.useMemo(t,e)};h.useReducer=function(t,e,n){return P.current.useReducer(t,e,n)};h.useRef=function(t){return P.current.useRef(t)};h.useState=function(t){return P.current.useState(t)};h.useSyncExternalStore=function(t,e,n){return P.current.useSyncExternalStore(t,e,n)};h.useTransition=function(){return P.current.useTransition()};h.version="18.3.1";Ge.exports=h;var en=Ge.exports;const Jt=Ve(en),Ro=Yn({__proto__:null,default:Jt},[en]);/*!
 * Font Awesome Free 6.7.2 by @fontawesome - https://fontawesome.com
 * License - https://fontawesome.com/license/free (Icons: CC BY 4.0, Fonts: SIL OFL 1.1, Code: MIT License)
 * Copyright 2024 Fonticons, Inc.
 */function or(t,e,n){return(e=sr(e))in t?Object.defineProperty(t,e,{value:n,enumerable:!0,configurable:!0,writable:!0}):t[e]=n,t}function pe(t,e){var n=Object.keys(t);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(t);e&&(r=r.filter(function(a){return Object.getOwnPropertyDescriptor(t,a).enumerable})),n.push.apply(n,r)}return n}function l(t){for(var e=1;e<arguments.length;e++){var n=arguments[e]!=null?arguments[e]:{};e%2?pe(Object(n),!0).forEach(function(r){or(t,r,n[r])}):Object.getOwnPropertyDescriptors?Object.defineProperties(t,Object.getOwnPropertyDescriptors(n)):pe(Object(n)).forEach(function(r){Object.defineProperty(t,r,Object.getOwnPropertyDescriptor(n,r))})}return t}function ir(t,e){if(typeof t!="object"||!t)return t;var n=t[Symbol.toPrimitive];if(n!==void 0){var r=n.call(t,e);if(typeof r!="object")return r;throw new TypeError("@@toPrimitive must return a primitive value.")}return(e==="string"?String:Number)(t)}function sr(t){var e=ir(t,"string");return typeof e=="symbol"?e:e+""}const ge=()=>{};let Zt={},nn={},rn=null,an={mark:ge,measure:ge};try{typeof window<"u"&&(Zt=window),typeof document<"u"&&(nn=document),typeof MutationObserver<"u"&&(rn=MutationObserver),typeof performance<"u"&&(an=performance)}catch{}const{userAgent:he=""}=Zt.navigator||{},D=Zt,y=nn,ye=rn,st=an;D.document;const F=!!y.documentElement&&!!y.head&&typeof y.addEventListener=="function"&&typeof y.createElement=="function",on=~he.indexOf("MSIE")||~he.indexOf("Trident/");var lr=/fa(s|r|l|t|d|dr|dl|dt|b|k|kd|ss|sr|sl|st|sds|sdr|sdl|sdt)?[\-\ ]/,fr=/Font ?Awesome ?([56 ]*)(Solid|Regular|Light|Thin|Duotone|Brands|Free|Pro|Sharp Duotone|Sharp|Kit)?.*/i,sn={classic:{fa:"solid",fas:"solid","fa-solid":"solid",far:"regular","fa-regular":"regular",fal:"light","fa-light":"light",fat:"thin","fa-thin":"thin",fab:"brands","fa-brands":"brands"},duotone:{fa:"solid",fad:"solid","fa-solid":"solid","fa-duotone":"solid",fadr:"regular","fa-regular":"regular",fadl:"light","fa-light":"light",fadt:"thin","fa-thin":"thin"},sharp:{fa:"solid",fass:"solid","fa-solid":"solid",fasr:"regular","fa-regular":"regular",fasl:"light","fa-light":"light",fast:"thin","fa-thin":"thin"},"sharp-duotone":{fa:"solid",fasds:"solid","fa-solid":"solid",fasdr:"regular","fa-regular":"regular",fasdl:"light","fa-light":"light",fasdt:"thin","fa-thin":"thin"}},cr={GROUP:"duotone-group",PRIMARY:"primary",SECONDARY:"secondary"},ln=["fa-classic","fa-duotone","fa-sharp","fa-sharp-duotone"],O="classic",ht="duotone",ur="sharp",dr="sharp-duotone",fn=[O,ht,ur,dr],mr={classic:{900:"fas",400:"far",normal:"far",300:"fal",100:"fat"},duotone:{900:"fad",400:"fadr",300:"fadl",100:"fadt"},sharp:{900:"fass",400:"fasr",300:"fasl",100:"fast"},"sharp-duotone":{900:"fasds",400:"fasdr",300:"fasdl",100:"fasdt"}},pr={"Font Awesome 6 Free":{900:"fas",400:"far"},"Font Awesome 6 Pro":{900:"fas",400:"far",normal:"far",300:"fal",100:"fat"},"Font Awesome 6 Brands":{400:"fab",normal:"fab"},"Font Awesome 6 Duotone":{900:"fad",400:"fadr",normal:"fadr",300:"fadl",100:"fadt"},"Font Awesome 6 Sharp":{900:"fass",400:"fasr",normal:"fasr",300:"fasl",100:"fast"},"Font Awesome 6 Sharp Duotone":{900:"fasds",400:"fasdr",normal:"fasdr",300:"fasdl",100:"fasdt"}},gr=new Map([["classic",{defaultShortPrefixId:"fas",defaultStyleId:"solid",styleIds:["solid","regular","light","thin","brands"],futureStyleIds:[],defaultFontWeight:900}],["sharp",{defaultShortPrefixId:"fass",defaultStyleId:"solid",styleIds:["solid","regular","light","thin"],futureStyleIds:[],defaultFontWeight:900}],["duotone",{defaultShortPrefixId:"fad",defaultStyleId:"solid",styleIds:["solid","regular","light","thin"],futureStyleIds:[],defaultFontWeight:900}],["sharp-duotone",{defaultShortPrefixId:"fasds",defaultStyleId:"solid",styleIds:["solid","regular","light","thin"],futureStyleIds:[],defaultFontWeight:900}]]),hr={classic:{solid:"fas",regular:"far",light:"fal",thin:"fat",brands:"fab"},duotone:{solid:"fad",regular:"fadr",light:"fadl",thin:"fadt"},sharp:{solid:"fass",regular:"fasr",light:"fasl",thin:"fast"},"sharp-duotone":{solid:"fasds",regular:"fasdr",light:"fasdl",thin:"fasdt"}},yr=["fak","fa-kit","fakd","fa-kit-duotone"],be={kit:{fak:"kit","fa-kit":"kit"},"kit-duotone":{fakd:"kit-duotone","fa-kit-duotone":"kit-duotone"}},br=["kit"],vr={kit:{"fa-kit":"fak"}},xr=["fak","fakd"],Ar={kit:{fak:"fa-kit"}},ve={kit:{kit:"fak"},"kit-duotone":{"kit-duotone":"fakd"}},lt={GROUP:"duotone-group",SWAP_OPACITY:"swap-opacity",PRIMARY:"primary",SECONDARY:"secondary"},wr=["fa-classic","fa-duotone","fa-sharp","fa-sharp-duotone"],Sr=["fak","fa-kit","fakd","fa-kit-duotone"],Or={"Font Awesome Kit":{400:"fak",normal:"fak"},"Font Awesome Kit Duotone":{400:"fakd",normal:"fakd"}},kr={classic:{"fa-brands":"fab","fa-duotone":"fad","fa-light":"fal","fa-regular":"far","fa-solid":"fas","fa-thin":"fat"},duotone:{"fa-regular":"fadr","fa-light":"fadl","fa-thin":"fadt"},sharp:{"fa-solid":"fass","fa-regular":"fasr","fa-light":"fasl","fa-thin":"fast"},"sharp-duotone":{"fa-solid":"fasds","fa-regular":"fasdr","fa-light":"fasdl","fa-thin":"fasdt"}},Pr={classic:["fas","far","fal","fat","fad"],duotone:["fadr","fadl","fadt"],sharp:["fass","fasr","fasl","fast"],"sharp-duotone":["fasds","fasdr","fasdl","fasdt"]},Et={classic:{fab:"fa-brands",fad:"fa-duotone",fal:"fa-light",far:"fa-regular",fas:"fa-solid",fat:"fa-thin"},duotone:{fadr:"fa-regular",fadl:"fa-light",fadt:"fa-thin"},sharp:{fass:"fa-solid",fasr:"fa-regular",fasl:"fa-light",fast:"fa-thin"},"sharp-duotone":{fasds:"fa-solid",fasdr:"fa-regular",fasdl:"fa-light",fasdt:"fa-thin"}},_r=["fa-solid","fa-regular","fa-light","fa-thin","fa-duotone","fa-brands"],It=["fa","fas","far","fal","fat","fad","fadr","fadl","fadt","fab","fass","fasr","fasl","fast","fasds","fasdr","fasdl","fasdt",...wr,..._r],Er=["solid","regular","light","thin","duotone","brands"],cn=[1,2,3,4,5,6,7,8,9,10],Ir=cn.concat([11,12,13,14,15,16,17,18,19,20]),Cr=[...Object.keys(Pr),...Er,"2xs","xs","sm","lg","xl","2xl","beat","border","fade","beat-fade","bounce","flip-both","flip-horizontal","flip-vertical","flip","fw","inverse","layers-counter","layers-text","layers","li","pull-left","pull-right","pulse","rotate-180","rotate-270","rotate-90","rotate-by","shake","spin-pulse","spin-reverse","spin","stack-1x","stack-2x","stack","ul",lt.GROUP,lt.SWAP_OPACITY,lt.PRIMARY,lt.SECONDARY].concat(cn.map(t=>"".concat(t,"x"))).concat(Ir.map(t=>"w-".concat(t))),Tr={"Font Awesome 5 Free":{900:"fas",400:"far"},"Font Awesome 5 Pro":{900:"fas",400:"far",normal:"far",300:"fal"},"Font Awesome 5 Brands":{400:"fab",normal:"fab"},"Font Awesome 5 Duotone":{900:"fad"}};const T="___FONT_AWESOME___",Ct=16,un="fa",dn="svg-inline--fa",W="data-fa-i2svg",Tt="data-fa-pseudo-element",Nr="data-fa-pseudo-element-pending",te="data-prefix",ee="data-icon",xe="fontawesome-i2svg",Fr="async",Rr=["HTML","HEAD","STYLE","SCRIPT"],mn=(()=>{try{return!0}catch{return!1}})();function rt(t){return new Proxy(t,{get(e,n){return n in e?e[n]:e[O]}})}const pn=l({},sn);pn[O]=l(l(l(l({},{"fa-duotone":"duotone"}),sn[O]),be.kit),be["kit-duotone"]);const Mr=rt(pn),Nt=l({},hr);Nt[O]=l(l(l(l({},{duotone:"fad"}),Nt[O]),ve.kit),ve["kit-duotone"]);const Ae=rt(Nt),Ft=l({},Et);Ft[O]=l(l({},Ft[O]),Ar.kit);const ne=rt(Ft),Rt=l({},kr);Rt[O]=l(l({},Rt[O]),vr.kit);rt(Rt);const jr=lr,gn="fa-layers-text",Lr=fr,Dr=l({},mr);rt(Dr);const zr=["class","data-prefix","data-icon","data-fa-transform","data-fa-mask"],wt=cr,$r=[...br,...Cr],J=D.FontAwesomeConfig||{};function Ur(t){var e=y.querySelector("script["+t+"]");if(e)return e.getAttribute(t)}function Wr(t){return t===""?!0:t==="false"?!1:t==="true"?!0:t}y&&typeof y.querySelector=="function"&&[["data-family-prefix","familyPrefix"],["data-css-prefix","cssPrefix"],["data-family-default","familyDefault"],["data-style-default","styleDefault"],["data-replacement-class","replacementClass"],["data-auto-replace-svg","autoReplaceSvg"],["data-auto-add-css","autoAddCss"],["data-auto-a11y","autoA11y"],["data-search-pseudo-elements","searchPseudoElements"],["data-observe-mutations","observeMutations"],["data-mutate-approach","mutateApproach"],["data-keep-original-source","keepOriginalSource"],["data-measure-performance","measurePerformance"],["data-show-missing-icons","showMissingIcons"]].forEach(e=>{let[n,r]=e;const a=Wr(Ur(n));a!=null&&(J[r]=a)});const hn={styleDefault:"solid",familyDefault:O,cssPrefix:un,replacementClass:dn,autoReplaceSvg:!0,autoAddCss:!0,autoA11y:!0,searchPseudoElements:!1,observeMutations:!0,mutateApproach:"async",keepOriginalSource:!0,measurePerformance:!1,showMissingIcons:!0};J.familyPrefix&&(J.cssPrefix=J.familyPrefix);const X=l(l({},hn),J);X.autoReplaceSvg||(X.observeMutations=!1);const d={};Object.keys(hn).forEach(t=>{Object.defineProperty(d,t,{enumerable:!0,set:function(e){X[t]=e,Z.forEach(n=>n(d))},get:function(){return X[t]}})});Object.defineProperty(d,"familyPrefix",{enumerable:!0,set:function(t){X.cssPrefix=t,Z.forEach(e=>e(d))},get:function(){return X.cssPrefix}});D.FontAwesomeConfig=d;const Z=[];function Yr(t){return Z.push(t),()=>{Z.splice(Z.indexOf(t),1)}}const j=Ct,I={size:16,x:0,y:0,rotate:0,flipX:!1,flipY:!1};function Hr(t){if(!t||!F)return;const e=y.createElement("style");e.setAttribute("type","text/css"),e.innerHTML=t;const n=y.head.childNodes;let r=null;for(let a=n.length-1;a>-1;a--){const o=n[a],i=(o.tagName||"").toUpperCase();["STYLE","LINK"].indexOf(i)>-1&&(r=o)}return y.head.insertBefore(e,r),t}const Vr="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";function tt(){let t=12,e="";for(;t-- >0;)e+=Vr[Math.random()*62|0];return e}function K(t){const e=[];for(let n=(t||[]).length>>>0;n--;)e[n]=t[n];return e}function re(t){return t.classList?K(t.classList):(t.getAttribute("class")||"").split(" ").filter(e=>e)}function yn(t){return"".concat(t).replace(/&/g,"&amp;").replace(/"/g,"&quot;").replace(/'/g,"&#39;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}function Gr(t){return Object.keys(t||{}).reduce((e,n)=>e+"".concat(n,'="').concat(yn(t[n]),'" '),"").trim()}function yt(t){return Object.keys(t||{}).reduce((e,n)=>e+"".concat(n,": ").concat(t[n].trim(),";"),"")}function ae(t){return t.size!==I.size||t.x!==I.x||t.y!==I.y||t.rotate!==I.rotate||t.flipX||t.flipY}function Br(t){let{transform:e,containerWidth:n,iconWidth:r}=t;const a={transform:"translate(".concat(n/2," 256)")},o="translate(".concat(e.x*32,", ").concat(e.y*32,") "),i="scale(".concat(e.size/16*(e.flipX?-1:1),", ").concat(e.size/16*(e.flipY?-1:1),") "),s="rotate(".concat(e.rotate," 0 0)"),f={transform:"".concat(o," ").concat(i," ").concat(s)},c={transform:"translate(".concat(r/2*-1," -256)")};return{outer:a,inner:f,path:c}}function Xr(t){let{transform:e,width:n=Ct,height:r=Ct,startCentered:a=!1}=t,o="";return a&&on?o+="translate(".concat(e.x/j-n/2,"em, ").concat(e.y/j-r/2,"em) "):a?o+="translate(calc(-50% + ".concat(e.x/j,"em), calc(-50% + ").concat(e.y/j,"em)) "):o+="translate(".concat(e.x/j,"em, ").concat(e.y/j,"em) "),o+="scale(".concat(e.size/j*(e.flipX?-1:1),", ").concat(e.size/j*(e.flipY?-1:1),") "),o+="rotate(".concat(e.rotate,"deg) "),o}var qr=`:root, :host {
  --fa-font-solid: normal 900 1em/1 "Font Awesome 6 Free";
  --fa-font-regular: normal 400 1em/1 "Font Awesome 6 Free";
  --fa-font-light: normal 300 1em/1 "Font Awesome 6 Pro";
  --fa-font-thin: normal 100 1em/1 "Font Awesome 6 Pro";
  --fa-font-duotone: normal 900 1em/1 "Font Awesome 6 Duotone";
  --fa-font-duotone-regular: normal 400 1em/1 "Font Awesome 6 Duotone";
  --fa-font-duotone-light: normal 300 1em/1 "Font Awesome 6 Duotone";
  --fa-font-duotone-thin: normal 100 1em/1 "Font Awesome 6 Duotone";
  --fa-font-brands: normal 400 1em/1 "Font Awesome 6 Brands";
  --fa-font-sharp-solid: normal 900 1em/1 "Font Awesome 6 Sharp";
  --fa-font-sharp-regular: normal 400 1em/1 "Font Awesome 6 Sharp";
  --fa-font-sharp-light: normal 300 1em/1 "Font Awesome 6 Sharp";
  --fa-font-sharp-thin: normal 100 1em/1 "Font Awesome 6 Sharp";
  --fa-font-sharp-duotone-solid: normal 900 1em/1 "Font Awesome 6 Sharp Duotone";
  --fa-font-sharp-duotone-regular: normal 400 1em/1 "Font Awesome 6 Sharp Duotone";
  --fa-font-sharp-duotone-light: normal 300 1em/1 "Font Awesome 6 Sharp Duotone";
  --fa-font-sharp-duotone-thin: normal 100 1em/1 "Font Awesome 6 Sharp Duotone";
}

svg:not(:root).svg-inline--fa, svg:not(:host).svg-inline--fa {
  overflow: visible;
  box-sizing: content-box;
}

.svg-inline--fa {
  display: var(--fa-display, inline-block);
  height: 1em;
  overflow: visible;
  vertical-align: -0.125em;
}
.svg-inline--fa.fa-2xs {
  vertical-align: 0.1em;
}
.svg-inline--fa.fa-xs {
  vertical-align: 0em;
}
.svg-inline--fa.fa-sm {
  vertical-align: -0.0714285705em;
}
.svg-inline--fa.fa-lg {
  vertical-align: -0.2em;
}
.svg-inline--fa.fa-xl {
  vertical-align: -0.25em;
}
.svg-inline--fa.fa-2xl {
  vertical-align: -0.3125em;
}
.svg-inline--fa.fa-pull-left {
  margin-right: var(--fa-pull-margin, 0.3em);
  width: auto;
}
.svg-inline--fa.fa-pull-right {
  margin-left: var(--fa-pull-margin, 0.3em);
  width: auto;
}
.svg-inline--fa.fa-li {
  width: var(--fa-li-width, 2em);
  top: 0.25em;
}
.svg-inline--fa.fa-fw {
  width: var(--fa-fw-width, 1.25em);
}

.fa-layers svg.svg-inline--fa {
  bottom: 0;
  left: 0;
  margin: auto;
  position: absolute;
  right: 0;
  top: 0;
}

.fa-layers-counter, .fa-layers-text {
  display: inline-block;
  position: absolute;
  text-align: center;
}

.fa-layers {
  display: inline-block;
  height: 1em;
  position: relative;
  text-align: center;
  vertical-align: -0.125em;
  width: 1em;
}
.fa-layers svg.svg-inline--fa {
  transform-origin: center center;
}

.fa-layers-text {
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  transform-origin: center center;
}

.fa-layers-counter {
  background-color: var(--fa-counter-background-color, #ff253a);
  border-radius: var(--fa-counter-border-radius, 1em);
  box-sizing: border-box;
  color: var(--fa-inverse, #fff);
  line-height: var(--fa-counter-line-height, 1);
  max-width: var(--fa-counter-max-width, 5em);
  min-width: var(--fa-counter-min-width, 1.5em);
  overflow: hidden;
  padding: var(--fa-counter-padding, 0.25em 0.5em);
  right: var(--fa-right, 0);
  text-overflow: ellipsis;
  top: var(--fa-top, 0);
  transform: scale(var(--fa-counter-scale, 0.25));
  transform-origin: top right;
}

.fa-layers-bottom-right {
  bottom: var(--fa-bottom, 0);
  right: var(--fa-right, 0);
  top: auto;
  transform: scale(var(--fa-layers-scale, 0.25));
  transform-origin: bottom right;
}

.fa-layers-bottom-left {
  bottom: var(--fa-bottom, 0);
  left: var(--fa-left, 0);
  right: auto;
  top: auto;
  transform: scale(var(--fa-layers-scale, 0.25));
  transform-origin: bottom left;
}

.fa-layers-top-right {
  top: var(--fa-top, 0);
  right: var(--fa-right, 0);
  transform: scale(var(--fa-layers-scale, 0.25));
  transform-origin: top right;
}

.fa-layers-top-left {
  left: var(--fa-left, 0);
  right: auto;
  top: var(--fa-top, 0);
  transform: scale(var(--fa-layers-scale, 0.25));
  transform-origin: top left;
}

.fa-1x {
  font-size: 1em;
}

.fa-2x {
  font-size: 2em;
}

.fa-3x {
  font-size: 3em;
}

.fa-4x {
  font-size: 4em;
}

.fa-5x {
  font-size: 5em;
}

.fa-6x {
  font-size: 6em;
}

.fa-7x {
  font-size: 7em;
}

.fa-8x {
  font-size: 8em;
}

.fa-9x {
  font-size: 9em;
}

.fa-10x {
  font-size: 10em;
}

.fa-2xs {
  font-size: 0.625em;
  line-height: 0.1em;
  vertical-align: 0.225em;
}

.fa-xs {
  font-size: 0.75em;
  line-height: 0.0833333337em;
  vertical-align: 0.125em;
}

.fa-sm {
  font-size: 0.875em;
  line-height: 0.0714285718em;
  vertical-align: 0.0535714295em;
}

.fa-lg {
  font-size: 1.25em;
  line-height: 0.05em;
  vertical-align: -0.075em;
}

.fa-xl {
  font-size: 1.5em;
  line-height: 0.0416666682em;
  vertical-align: -0.125em;
}

.fa-2xl {
  font-size: 2em;
  line-height: 0.03125em;
  vertical-align: -0.1875em;
}

.fa-fw {
  text-align: center;
  width: 1.25em;
}

.fa-ul {
  list-style-type: none;
  margin-left: var(--fa-li-margin, 2.5em);
  padding-left: 0;
}
.fa-ul > li {
  position: relative;
}

.fa-li {
  left: calc(-1 * var(--fa-li-width, 2em));
  position: absolute;
  text-align: center;
  width: var(--fa-li-width, 2em);
  line-height: inherit;
}

.fa-border {
  border-color: var(--fa-border-color, #eee);
  border-radius: var(--fa-border-radius, 0.1em);
  border-style: var(--fa-border-style, solid);
  border-width: var(--fa-border-width, 0.08em);
  padding: var(--fa-border-padding, 0.2em 0.25em 0.15em);
}

.fa-pull-left {
  float: left;
  margin-right: var(--fa-pull-margin, 0.3em);
}

.fa-pull-right {
  float: right;
  margin-left: var(--fa-pull-margin, 0.3em);
}

.fa-beat {
  animation-name: fa-beat;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, ease-in-out);
}

.fa-bounce {
  animation-name: fa-bounce;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, cubic-bezier(0.28, 0.84, 0.42, 1));
}

.fa-fade {
  animation-name: fa-fade;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, cubic-bezier(0.4, 0, 0.6, 1));
}

.fa-beat-fade {
  animation-name: fa-beat-fade;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, cubic-bezier(0.4, 0, 0.6, 1));
}

.fa-flip {
  animation-name: fa-flip;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, ease-in-out);
}

.fa-shake {
  animation-name: fa-shake;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, linear);
}

.fa-spin {
  animation-name: fa-spin;
  animation-delay: var(--fa-animation-delay, 0s);
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 2s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, linear);
}

.fa-spin-reverse {
  --fa-animation-direction: reverse;
}

.fa-pulse,
.fa-spin-pulse {
  animation-name: fa-spin;
  animation-direction: var(--fa-animation-direction, normal);
  animation-duration: var(--fa-animation-duration, 1s);
  animation-iteration-count: var(--fa-animation-iteration-count, infinite);
  animation-timing-function: var(--fa-animation-timing, steps(8));
}

@media (prefers-reduced-motion: reduce) {
  .fa-beat,
.fa-bounce,
.fa-fade,
.fa-beat-fade,
.fa-flip,
.fa-pulse,
.fa-shake,
.fa-spin,
.fa-spin-pulse {
    animation-delay: -1ms;
    animation-duration: 1ms;
    animation-iteration-count: 1;
    transition-delay: 0s;
    transition-duration: 0s;
  }
}
@keyframes fa-beat {
  0%, 90% {
    transform: scale(1);
  }
  45% {
    transform: scale(var(--fa-beat-scale, 1.25));
  }
}
@keyframes fa-bounce {
  0% {
    transform: scale(1, 1) translateY(0);
  }
  10% {
    transform: scale(var(--fa-bounce-start-scale-x, 1.1), var(--fa-bounce-start-scale-y, 0.9)) translateY(0);
  }
  30% {
    transform: scale(var(--fa-bounce-jump-scale-x, 0.9), var(--fa-bounce-jump-scale-y, 1.1)) translateY(var(--fa-bounce-height, -0.5em));
  }
  50% {
    transform: scale(var(--fa-bounce-land-scale-x, 1.05), var(--fa-bounce-land-scale-y, 0.95)) translateY(0);
  }
  57% {
    transform: scale(1, 1) translateY(var(--fa-bounce-rebound, -0.125em));
  }
  64% {
    transform: scale(1, 1) translateY(0);
  }
  100% {
    transform: scale(1, 1) translateY(0);
  }
}
@keyframes fa-fade {
  50% {
    opacity: var(--fa-fade-opacity, 0.4);
  }
}
@keyframes fa-beat-fade {
  0%, 100% {
    opacity: var(--fa-beat-fade-opacity, 0.4);
    transform: scale(1);
  }
  50% {
    opacity: 1;
    transform: scale(var(--fa-beat-fade-scale, 1.125));
  }
}
@keyframes fa-flip {
  50% {
    transform: rotate3d(var(--fa-flip-x, 0), var(--fa-flip-y, 1), var(--fa-flip-z, 0), var(--fa-flip-angle, -180deg));
  }
}
@keyframes fa-shake {
  0% {
    transform: rotate(-15deg);
  }
  4% {
    transform: rotate(15deg);
  }
  8%, 24% {
    transform: rotate(-18deg);
  }
  12%, 28% {
    transform: rotate(18deg);
  }
  16% {
    transform: rotate(-22deg);
  }
  20% {
    transform: rotate(22deg);
  }
  32% {
    transform: rotate(-12deg);
  }
  36% {
    transform: rotate(12deg);
  }
  40%, 100% {
    transform: rotate(0deg);
  }
}
@keyframes fa-spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}
.fa-rotate-90 {
  transform: rotate(90deg);
}

.fa-rotate-180 {
  transform: rotate(180deg);
}

.fa-rotate-270 {
  transform: rotate(270deg);
}

.fa-flip-horizontal {
  transform: scale(-1, 1);
}

.fa-flip-vertical {
  transform: scale(1, -1);
}

.fa-flip-both,
.fa-flip-horizontal.fa-flip-vertical {
  transform: scale(-1, -1);
}

.fa-rotate-by {
  transform: rotate(var(--fa-rotate-angle, 0));
}

.fa-stack {
  display: inline-block;
  vertical-align: middle;
  height: 2em;
  position: relative;
  width: 2.5em;
}

.fa-stack-1x,
.fa-stack-2x {
  bottom: 0;
  left: 0;
  margin: auto;
  position: absolute;
  right: 0;
  top: 0;
  z-index: var(--fa-stack-z-index, auto);
}

.svg-inline--fa.fa-stack-1x {
  height: 1em;
  width: 1.25em;
}
.svg-inline--fa.fa-stack-2x {
  height: 2em;
  width: 2.5em;
}

.fa-inverse {
  color: var(--fa-inverse, #fff);
}

.sr-only,
.fa-sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}

.sr-only-focusable:not(:focus),
.fa-sr-only-focusable:not(:focus) {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}

.svg-inline--fa .fa-primary {
  fill: var(--fa-primary-color, currentColor);
  opacity: var(--fa-primary-opacity, 1);
}

.svg-inline--fa .fa-secondary {
  fill: var(--fa-secondary-color, currentColor);
  opacity: var(--fa-secondary-opacity, 0.4);
}

.svg-inline--fa.fa-swap-opacity .fa-primary {
  opacity: var(--fa-secondary-opacity, 0.4);
}

.svg-inline--fa.fa-swap-opacity .fa-secondary {
  opacity: var(--fa-primary-opacity, 1);
}

.svg-inline--fa mask .fa-primary,
.svg-inline--fa mask .fa-secondary {
  fill: black;
}`;function bn(){const t=un,e=dn,n=d.cssPrefix,r=d.replacementClass;let a=qr;if(n!==t||r!==e){const o=new RegExp("\\.".concat(t,"\\-"),"g"),i=new RegExp("\\--".concat(t,"\\-"),"g"),s=new RegExp("\\.".concat(e),"g");a=a.replace(o,".".concat(n,"-")).replace(i,"--".concat(n,"-")).replace(s,".".concat(r))}return a}let we=!1;function St(){d.autoAddCss&&!we&&(Hr(bn()),we=!0)}var Kr={mixout(){return{dom:{css:bn,insertCss:St}}},hooks(){return{beforeDOMElementCreation(){St()},beforeI2svg(){St()}}}};const N=D||{};N[T]||(N[T]={});N[T].styles||(N[T].styles={});N[T].hooks||(N[T].hooks={});N[T].shims||(N[T].shims=[]);var C=N[T];const vn=[],xn=function(){y.removeEventListener("DOMContentLoaded",xn),mt=1,vn.map(t=>t())};let mt=!1;F&&(mt=(y.documentElement.doScroll?/^loaded|^c/:/^loaded|^i|^c/).test(y.readyState),mt||y.addEventListener("DOMContentLoaded",xn));function Qr(t){F&&(mt?setTimeout(t,0):vn.push(t))}function at(t){const{tag:e,attributes:n={},children:r=[]}=t;return typeof t=="string"?yn(t):"<".concat(e," ").concat(Gr(n),">").concat(r.map(at).join(""),"</").concat(e,">")}function Se(t,e,n){if(t&&t[e]&&t[e][n])return{prefix:e,iconName:n,icon:t[e][n]}}var Ot=function(e,n,r,a){var o=Object.keys(e),i=o.length,s=n,f,c,u;for(r===void 0?(f=1,u=e[o[0]]):(f=0,u=r);f<i;f++)c=o[f],u=s(u,e[c],c,e);return u};function Jr(t){const e=[];let n=0;const r=t.length;for(;n<r;){const a=t.charCodeAt(n++);if(a>=55296&&a<=56319&&n<r){const o=t.charCodeAt(n++);(o&64512)==56320?e.push(((a&1023)<<10)+(o&1023)+65536):(e.push(a),n--)}else e.push(a)}return e}function Mt(t){const e=Jr(t);return e.length===1?e[0].toString(16):null}function Zr(t,e){const n=t.length;let r=t.charCodeAt(e),a;return r>=55296&&r<=56319&&n>e+1&&(a=t.charCodeAt(e+1),a>=56320&&a<=57343)?(r-55296)*1024+a-56320+65536:r}function Oe(t){return Object.keys(t).reduce((e,n)=>{const r=t[n];return!!r.icon?e[r.iconName]=r.icon:e[n]=r,e},{})}function jt(t,e){let n=arguments.length>2&&arguments[2]!==void 0?arguments[2]:{};const{skipHooks:r=!1}=n,a=Oe(e);typeof C.hooks.addPack=="function"&&!r?C.hooks.addPack(t,Oe(e)):C.styles[t]=l(l({},C.styles[t]||{}),a),t==="fas"&&jt("fa",e)}const{styles:et,shims:ta}=C,An=Object.keys(ne),ea=An.reduce((t,e)=>(t[e]=Object.keys(ne[e]),t),{});let oe=null,wn={},Sn={},On={},kn={},Pn={};function na(t){return~$r.indexOf(t)}function ra(t,e){const n=e.split("-"),r=n[0],a=n.slice(1).join("-");return r===t&&a!==""&&!na(a)?a:null}const _n=()=>{const t=r=>Ot(et,(a,o,i)=>(a[i]=Ot(o,r,{}),a),{});wn=t((r,a,o)=>(a[3]&&(r[a[3]]=o),a[2]&&a[2].filter(s=>typeof s=="number").forEach(s=>{r[s.toString(16)]=o}),r)),Sn=t((r,a,o)=>(r[o]=o,a[2]&&a[2].filter(s=>typeof s=="string").forEach(s=>{r[s]=o}),r)),Pn=t((r,a,o)=>{const i=a[2];return r[o]=o,i.forEach(s=>{r[s]=o}),r});const e="far"in et||d.autoFetchSvg,n=Ot(ta,(r,a)=>{const o=a[0];let i=a[1];const s=a[2];return i==="far"&&!e&&(i="fas"),typeof o=="string"&&(r.names[o]={prefix:i,iconName:s}),typeof o=="number"&&(r.unicodes[o.toString(16)]={prefix:i,iconName:s}),r},{names:{},unicodes:{}});On=n.names,kn=n.unicodes,oe=bt(d.styleDefault,{family:d.familyDefault})};Yr(t=>{oe=bt(t.styleDefault,{family:d.familyDefault})});_n();function ie(t,e){return(wn[t]||{})[e]}function aa(t,e){return(Sn[t]||{})[e]}function U(t,e){return(Pn[t]||{})[e]}function En(t){return On[t]||{prefix:null,iconName:null}}function oa(t){const e=kn[t],n=ie("fas",t);return e||(n?{prefix:"fas",iconName:n}:null)||{prefix:null,iconName:null}}function z(){return oe}const In=()=>({prefix:null,iconName:null,rest:[]});function ia(t){let e=O;const n=An.reduce((r,a)=>(r[a]="".concat(d.cssPrefix,"-").concat(a),r),{});return fn.forEach(r=>{(t.includes(n[r])||t.some(a=>ea[r].includes(a)))&&(e=r)}),e}function bt(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{family:n=O}=e,r=Mr[n][t];if(n===ht&&!t)return"fad";const a=Ae[n][t]||Ae[n][r],o=t in C.styles?t:null;return a||o||null}function sa(t){let e=[],n=null;return t.forEach(r=>{const a=ra(d.cssPrefix,r);a?n=a:r&&e.push(r)}),{iconName:n,rest:e}}function ke(t){return t.sort().filter((e,n,r)=>r.indexOf(e)===n)}function vt(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{skipLookups:n=!1}=e;let r=null;const a=It.concat(Sr),o=ke(t.filter(g=>a.includes(g))),i=ke(t.filter(g=>!It.includes(g))),s=o.filter(g=>(r=g,!ln.includes(g))),[f=null]=s,c=ia(o),u=l(l({},sa(i)),{},{prefix:bt(f,{family:c})});return l(l(l({},u),ua({values:t,family:c,styles:et,config:d,canonical:u,givenPrefix:r})),la(n,r,u))}function la(t,e,n){let{prefix:r,iconName:a}=n;if(t||!r||!a)return{prefix:r,iconName:a};const o=e==="fa"?En(a):{},i=U(r,a);return a=o.iconName||i||a,r=o.prefix||r,r==="far"&&!et.far&&et.fas&&!d.autoFetchSvg&&(r="fas"),{prefix:r,iconName:a}}const fa=fn.filter(t=>t!==O||t!==ht),ca=Object.keys(Et).filter(t=>t!==O).map(t=>Object.keys(Et[t])).flat();function ua(t){const{values:e,family:n,canonical:r,givenPrefix:a="",styles:o={},config:i={}}=t,s=n===ht,f=e.includes("fa-duotone")||e.includes("fad"),c=i.familyDefault==="duotone",u=r.prefix==="fad"||r.prefix==="fa-duotone";if(!s&&(f||c||u)&&(r.prefix="fad"),(e.includes("fa-brands")||e.includes("fab"))&&(r.prefix="fab"),!r.prefix&&fa.includes(n)&&(Object.keys(o).find(m=>ca.includes(m))||i.autoFetchSvg)){const m=gr.get(n).defaultShortPrefixId;r.prefix=m,r.iconName=U(r.prefix,r.iconName)||r.iconName}return(r.prefix==="fa"||a==="fa")&&(r.prefix=z()||"fas"),r}class da{constructor(){this.definitions={}}add(){for(var e=arguments.length,n=new Array(e),r=0;r<e;r++)n[r]=arguments[r];const a=n.reduce(this._pullDefinitions,{});Object.keys(a).forEach(o=>{this.definitions[o]=l(l({},this.definitions[o]||{}),a[o]),jt(o,a[o]);const i=ne[O][o];i&&jt(i,a[o]),_n()})}reset(){this.definitions={}}_pullDefinitions(e,n){const r=n.prefix&&n.iconName&&n.icon?{0:n}:n;return Object.keys(r).map(a=>{const{prefix:o,iconName:i,icon:s}=r[a],f=s[2];e[o]||(e[o]={}),f.length>0&&f.forEach(c=>{typeof c=="string"&&(e[o][c]=s)}),e[o][i]=s}),e}}let Pe=[],G={};const B={},ma=Object.keys(B);function pa(t,e){let{mixoutsTo:n}=e;return Pe=t,G={},Object.keys(B).forEach(r=>{ma.indexOf(r)===-1&&delete B[r]}),Pe.forEach(r=>{const a=r.mixout?r.mixout():{};if(Object.keys(a).forEach(o=>{typeof a[o]=="function"&&(n[o]=a[o]),typeof a[o]=="object"&&Object.keys(a[o]).forEach(i=>{n[o]||(n[o]={}),n[o][i]=a[o][i]})}),r.hooks){const o=r.hooks();Object.keys(o).forEach(i=>{G[i]||(G[i]=[]),G[i].push(o[i])})}r.provides&&r.provides(B)}),n}function Lt(t,e){for(var n=arguments.length,r=new Array(n>2?n-2:0),a=2;a<n;a++)r[a-2]=arguments[a];return(G[t]||[]).forEach(i=>{e=i.apply(null,[e,...r])}),e}function Y(t){for(var e=arguments.length,n=new Array(e>1?e-1:0),r=1;r<e;r++)n[r-1]=arguments[r];(G[t]||[]).forEach(o=>{o.apply(null,n)})}function $(){const t=arguments[0],e=Array.prototype.slice.call(arguments,1);return B[t]?B[t].apply(null,e):void 0}function Dt(t){t.prefix==="fa"&&(t.prefix="fas");let{iconName:e}=t;const n=t.prefix||z();if(e)return e=U(n,e)||e,Se(Cn.definitions,n,e)||Se(C.styles,n,e)}const Cn=new da,ga=()=>{d.autoReplaceSvg=!1,d.observeMutations=!1,Y("noAuto")},ha={i2svg:function(){let t=arguments.length>0&&arguments[0]!==void 0?arguments[0]:{};return F?(Y("beforeI2svg",t),$("pseudoElements2svg",t),$("i2svg",t)):Promise.reject(new Error("Operation requires a DOM of some kind."))},watch:function(){let t=arguments.length>0&&arguments[0]!==void 0?arguments[0]:{};const{autoReplaceSvgRoot:e}=t;d.autoReplaceSvg===!1&&(d.autoReplaceSvg=!0),d.observeMutations=!0,Qr(()=>{ba({autoReplaceSvgRoot:e}),Y("watch",t)})}},ya={icon:t=>{if(t===null)return null;if(typeof t=="object"&&t.prefix&&t.iconName)return{prefix:t.prefix,iconName:U(t.prefix,t.iconName)||t.iconName};if(Array.isArray(t)&&t.length===2){const e=t[1].indexOf("fa-")===0?t[1].slice(3):t[1],n=bt(t[0]);return{prefix:n,iconName:U(n,e)||e}}if(typeof t=="string"&&(t.indexOf("".concat(d.cssPrefix,"-"))>-1||t.match(jr))){const e=vt(t.split(" "),{skipLookups:!0});return{prefix:e.prefix||z(),iconName:U(e.prefix,e.iconName)||e.iconName}}if(typeof t=="string"){const e=z();return{prefix:e,iconName:U(e,t)||t}}}},_={noAuto:ga,config:d,dom:ha,parse:ya,library:Cn,findIconDefinition:Dt,toHtml:at},ba=function(){let t=arguments.length>0&&arguments[0]!==void 0?arguments[0]:{};const{autoReplaceSvgRoot:e=y}=t;(Object.keys(C.styles).length>0||d.autoFetchSvg)&&F&&d.autoReplaceSvg&&_.dom.i2svg({node:e})};function xt(t,e){return Object.defineProperty(t,"abstract",{get:e}),Object.defineProperty(t,"html",{get:function(){return t.abstract.map(n=>at(n))}}),Object.defineProperty(t,"node",{get:function(){if(!F)return;const n=y.createElement("div");return n.innerHTML=t.html,n.children}}),t}function va(t){let{children:e,main:n,mask:r,attributes:a,styles:o,transform:i}=t;if(ae(i)&&n.found&&!r.found){const{width:s,height:f}=n,c={x:s/f/2,y:.5};a.style=yt(l(l({},o),{},{"transform-origin":"".concat(c.x+i.x/16,"em ").concat(c.y+i.y/16,"em")}))}return[{tag:"svg",attributes:a,children:e}]}function xa(t){let{prefix:e,iconName:n,children:r,attributes:a,symbol:o}=t;const i=o===!0?"".concat(e,"-").concat(d.cssPrefix,"-").concat(n):o;return[{tag:"svg",attributes:{style:"display: none;"},children:[{tag:"symbol",attributes:l(l({},a),{},{id:i}),children:r}]}]}function se(t){const{icons:{main:e,mask:n},prefix:r,iconName:a,transform:o,symbol:i,title:s,maskId:f,titleId:c,extra:u,watchable:g=!1}=t,{width:m,height:A}=n.found?n:e,k=xr.includes(r),w=[d.replacementClass,a?"".concat(d.cssPrefix,"-").concat(a):""].filter(M=>u.classes.indexOf(M)===-1).filter(M=>M!==""||!!M).concat(u.classes).join(" ");let v={children:[],attributes:l(l({},u.attributes),{},{"data-prefix":r,"data-icon":a,class:w,role:u.attributes.role||"img",xmlns:"http://www.w3.org/2000/svg",viewBox:"0 0 ".concat(m," ").concat(A)})};const b=k&&!~u.classes.indexOf("fa-fw")?{width:"".concat(m/A*16*.0625,"em")}:{};g&&(v.attributes[W]=""),s&&(v.children.push({tag:"title",attributes:{id:v.attributes["aria-labelledby"]||"title-".concat(c||tt())},children:[s]}),delete v.attributes.title);const x=l(l({},v),{},{prefix:r,iconName:a,main:e,mask:n,maskId:f,transform:o,symbol:i,styles:l(l({},b),u.styles)}),{children:S,attributes:R}=n.found&&e.found?$("generateAbstractMask",x)||{children:[],attributes:{}}:$("generateAbstractIcon",x)||{children:[],attributes:{}};return x.children=S,x.attributes=R,i?xa(x):va(x)}function _e(t){const{content:e,width:n,height:r,transform:a,title:o,extra:i,watchable:s=!1}=t,f=l(l(l({},i.attributes),o?{title:o}:{}),{},{class:i.classes.join(" ")});s&&(f[W]="");const c=l({},i.styles);ae(a)&&(c.transform=Xr({transform:a,startCentered:!0,width:n,height:r}),c["-webkit-transform"]=c.transform);const u=yt(c);u.length>0&&(f.style=u);const g=[];return g.push({tag:"span",attributes:f,children:[e]}),o&&g.push({tag:"span",attributes:{class:"sr-only"},children:[o]}),g}function Aa(t){const{content:e,title:n,extra:r}=t,a=l(l(l({},r.attributes),n?{title:n}:{}),{},{class:r.classes.join(" ")}),o=yt(r.styles);o.length>0&&(a.style=o);const i=[];return i.push({tag:"span",attributes:a,children:[e]}),n&&i.push({tag:"span",attributes:{class:"sr-only"},children:[n]}),i}const{styles:kt}=C;function zt(t){const e=t[0],n=t[1],[r]=t.slice(4);let a=null;return Array.isArray(r)?a={tag:"g",attributes:{class:"".concat(d.cssPrefix,"-").concat(wt.GROUP)},children:[{tag:"path",attributes:{class:"".concat(d.cssPrefix,"-").concat(wt.SECONDARY),fill:"currentColor",d:r[0]}},{tag:"path",attributes:{class:"".concat(d.cssPrefix,"-").concat(wt.PRIMARY),fill:"currentColor",d:r[1]}}]}:a={tag:"path",attributes:{fill:"currentColor",d:r}},{found:!0,width:e,height:n,icon:a}}const wa={found:!1,width:512,height:512};function Sa(t,e){!mn&&!d.showMissingIcons&&t&&console.error('Icon with name "'.concat(t,'" and prefix "').concat(e,'" is missing.'))}function $t(t,e){let n=e;return e==="fa"&&d.styleDefault!==null&&(e=z()),new Promise((r,a)=>{if(n==="fa"){const o=En(t)||{};t=o.iconName||t,e=o.prefix||e}if(t&&e&&kt[e]&&kt[e][t]){const o=kt[e][t];return r(zt(o))}Sa(t,e),r(l(l({},wa),{},{icon:d.showMissingIcons&&t?$("missingIconAbstract")||{}:{}}))})}const Ee=()=>{},Ut=d.measurePerformance&&st&&st.mark&&st.measure?st:{mark:Ee,measure:Ee},Q='FA "6.7.2"',Oa=t=>(Ut.mark("".concat(Q," ").concat(t," begins")),()=>Tn(t)),Tn=t=>{Ut.mark("".concat(Q," ").concat(t," ends")),Ut.measure("".concat(Q," ").concat(t),"".concat(Q," ").concat(t," begins"),"".concat(Q," ").concat(t," ends"))};var le={begin:Oa,end:Tn};const ut=()=>{};function Ie(t){return typeof(t.getAttribute?t.getAttribute(W):null)=="string"}function ka(t){const e=t.getAttribute?t.getAttribute(te):null,n=t.getAttribute?t.getAttribute(ee):null;return e&&n}function Pa(t){return t&&t.classList&&t.classList.contains&&t.classList.contains(d.replacementClass)}function _a(){return d.autoReplaceSvg===!0?dt.replace:dt[d.autoReplaceSvg]||dt.replace}function Ea(t){return y.createElementNS("http://www.w3.org/2000/svg",t)}function Ia(t){return y.createElement(t)}function Nn(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{ceFn:n=t.tag==="svg"?Ea:Ia}=e;if(typeof t=="string")return y.createTextNode(t);const r=n(t.tag);return Object.keys(t.attributes||[]).forEach(function(o){r.setAttribute(o,t.attributes[o])}),(t.children||[]).forEach(function(o){r.appendChild(Nn(o,{ceFn:n}))}),r}function Ca(t){let e=" ".concat(t.outerHTML," ");return e="".concat(e,"Font Awesome fontawesome.com "),e}const dt={replace:function(t){const e=t[0];if(e.parentNode)if(t[1].forEach(n=>{e.parentNode.insertBefore(Nn(n),e)}),e.getAttribute(W)===null&&d.keepOriginalSource){let n=y.createComment(Ca(e));e.parentNode.replaceChild(n,e)}else e.remove()},nest:function(t){const e=t[0],n=t[1];if(~re(e).indexOf(d.replacementClass))return dt.replace(t);const r=new RegExp("".concat(d.cssPrefix,"-.*"));if(delete n[0].attributes.id,n[0].attributes.class){const o=n[0].attributes.class.split(" ").reduce((i,s)=>(s===d.replacementClass||s.match(r)?i.toSvg.push(s):i.toNode.push(s),i),{toNode:[],toSvg:[]});n[0].attributes.class=o.toSvg.join(" "),o.toNode.length===0?e.removeAttribute("class"):e.setAttribute("class",o.toNode.join(" "))}const a=n.map(o=>at(o)).join(`
`);e.setAttribute(W,""),e.innerHTML=a}};function Ce(t){t()}function Fn(t,e){const n=typeof e=="function"?e:ut;if(t.length===0)n();else{let r=Ce;d.mutateApproach===Fr&&(r=D.requestAnimationFrame||Ce),r(()=>{const a=_a(),o=le.begin("mutate");t.map(a),o(),n()})}}let fe=!1;function Rn(){fe=!0}function Wt(){fe=!1}let pt=null;function Te(t){if(!ye||!d.observeMutations)return;const{treeCallback:e=ut,nodeCallback:n=ut,pseudoElementsCallback:r=ut,observeMutationsRoot:a=y}=t;pt=new ye(o=>{if(fe)return;const i=z();K(o).forEach(s=>{if(s.type==="childList"&&s.addedNodes.length>0&&!Ie(s.addedNodes[0])&&(d.searchPseudoElements&&r(s.target),e(s.target)),s.type==="attributes"&&s.target.parentNode&&d.searchPseudoElements&&r(s.target.parentNode),s.type==="attributes"&&Ie(s.target)&&~zr.indexOf(s.attributeName))if(s.attributeName==="class"&&ka(s.target)){const{prefix:f,iconName:c}=vt(re(s.target));s.target.setAttribute(te,f||i),c&&s.target.setAttribute(ee,c)}else Pa(s.target)&&n(s.target)})}),F&&pt.observe(a,{childList:!0,attributes:!0,characterData:!0,subtree:!0})}function Ta(){pt&&pt.disconnect()}function Na(t){const e=t.getAttribute("style");let n=[];return e&&(n=e.split(";").reduce((r,a)=>{const o=a.split(":"),i=o[0],s=o.slice(1);return i&&s.length>0&&(r[i]=s.join(":").trim()),r},{})),n}function Fa(t){const e=t.getAttribute("data-prefix"),n=t.getAttribute("data-icon"),r=t.innerText!==void 0?t.innerText.trim():"";let a=vt(re(t));return a.prefix||(a.prefix=z()),e&&n&&(a.prefix=e,a.iconName=n),a.iconName&&a.prefix||(a.prefix&&r.length>0&&(a.iconName=aa(a.prefix,t.innerText)||ie(a.prefix,Mt(t.innerText))),!a.iconName&&d.autoFetchSvg&&t.firstChild&&t.firstChild.nodeType===Node.TEXT_NODE&&(a.iconName=t.firstChild.data)),a}function Ra(t){const e=K(t.attributes).reduce((a,o)=>(a.name!=="class"&&a.name!=="style"&&(a[o.name]=o.value),a),{}),n=t.getAttribute("title"),r=t.getAttribute("data-fa-title-id");return d.autoA11y&&(n?e["aria-labelledby"]="".concat(d.replacementClass,"-title-").concat(r||tt()):(e["aria-hidden"]="true",e.focusable="false")),e}function Ma(){return{iconName:null,title:null,titleId:null,prefix:null,transform:I,symbol:!1,mask:{iconName:null,prefix:null,rest:[]},maskId:null,extra:{classes:[],styles:{},attributes:{}}}}function Ne(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{styleParser:!0};const{iconName:n,prefix:r,rest:a}=Fa(t),o=Ra(t),i=Lt("parseNodeAttributes",{},t);let s=e.styleParser?Na(t):[];return l({iconName:n,title:t.getAttribute("title"),titleId:t.getAttribute("data-fa-title-id"),prefix:r,transform:I,mask:{iconName:null,prefix:null,rest:[]},maskId:null,symbol:!1,extra:{classes:a,styles:s,attributes:o}},i)}const{styles:ja}=C;function Mn(t){const e=d.autoReplaceSvg==="nest"?Ne(t,{styleParser:!1}):Ne(t);return~e.extra.classes.indexOf(gn)?$("generateLayersText",t,e):$("generateSvgReplacementMutation",t,e)}function La(){return[...yr,...It]}function Fe(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:null;if(!F)return Promise.resolve();const n=y.documentElement.classList,r=u=>n.add("".concat(xe,"-").concat(u)),a=u=>n.remove("".concat(xe,"-").concat(u)),o=d.autoFetchSvg?La():ln.concat(Object.keys(ja));o.includes("fa")||o.push("fa");const i=[".".concat(gn,":not([").concat(W,"])")].concat(o.map(u=>".".concat(u,":not([").concat(W,"])"))).join(", ");if(i.length===0)return Promise.resolve();let s=[];try{s=K(t.querySelectorAll(i))}catch{}if(s.length>0)r("pending"),a("complete");else return Promise.resolve();const f=le.begin("onTree"),c=s.reduce((u,g)=>{try{const m=Mn(g);m&&u.push(m)}catch(m){mn||m.name==="MissingIcon"&&console.error(m)}return u},[]);return new Promise((u,g)=>{Promise.all(c).then(m=>{Fn(m,()=>{r("active"),r("complete"),a("pending"),typeof e=="function"&&e(),f(),u()})}).catch(m=>{f(),g(m)})})}function Da(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:null;Mn(t).then(n=>{n&&Fn([n],e)})}function za(t){return function(e){let n=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const r=(e||{}).icon?e:Dt(e||{});let{mask:a}=n;return a&&(a=(a||{}).icon?a:Dt(a||{})),t(r,l(l({},n),{},{mask:a}))}}const $a=function(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{transform:n=I,symbol:r=!1,mask:a=null,maskId:o=null,title:i=null,titleId:s=null,classes:f=[],attributes:c={},styles:u={}}=e;if(!t)return;const{prefix:g,iconName:m,icon:A}=t;return xt(l({type:"icon"},t),()=>(Y("beforeDOMElementCreation",{iconDefinition:t,params:e}),d.autoA11y&&(i?c["aria-labelledby"]="".concat(d.replacementClass,"-title-").concat(s||tt()):(c["aria-hidden"]="true",c.focusable="false")),se({icons:{main:zt(A),mask:a?zt(a.icon):{found:!1,width:null,height:null,icon:{}}},prefix:g,iconName:m,transform:l(l({},I),n),symbol:r,title:i,maskId:o,titleId:s,extra:{attributes:c,styles:u,classes:f}})))};var Ua={mixout(){return{icon:za($a)}},hooks(){return{mutationObserverCallbacks(t){return t.treeCallback=Fe,t.nodeCallback=Da,t}}},provides(t){t.i2svg=function(e){const{node:n=y,callback:r=()=>{}}=e;return Fe(n,r)},t.generateSvgReplacementMutation=function(e,n){const{iconName:r,title:a,titleId:o,prefix:i,transform:s,symbol:f,mask:c,maskId:u,extra:g}=n;return new Promise((m,A)=>{Promise.all([$t(r,i),c.iconName?$t(c.iconName,c.prefix):Promise.resolve({found:!1,width:512,height:512,icon:{}})]).then(k=>{let[w,v]=k;m([e,se({icons:{main:w,mask:v},prefix:i,iconName:r,transform:s,symbol:f,maskId:u,title:a,titleId:o,extra:g,watchable:!0})])}).catch(A)})},t.generateAbstractIcon=function(e){let{children:n,attributes:r,main:a,transform:o,styles:i}=e;const s=yt(i);s.length>0&&(r.style=s);let f;return ae(o)&&(f=$("generateAbstractTransformGrouping",{main:a,transform:o,containerWidth:a.width,iconWidth:a.width})),n.push(f||a.icon),{children:n,attributes:r}}}},Wa={mixout(){return{layer(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{classes:n=[]}=e;return xt({type:"layer"},()=>{Y("beforeDOMElementCreation",{assembler:t,params:e});let r=[];return t(a=>{Array.isArray(a)?a.map(o=>{r=r.concat(o.abstract)}):r=r.concat(a.abstract)}),[{tag:"span",attributes:{class:["".concat(d.cssPrefix,"-layers"),...n].join(" ")},children:r}]})}}}},Ya={mixout(){return{counter(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{title:n=null,classes:r=[],attributes:a={},styles:o={}}=e;return xt({type:"counter",content:t},()=>(Y("beforeDOMElementCreation",{content:t,params:e}),Aa({content:t.toString(),title:n,extra:{attributes:a,styles:o,classes:["".concat(d.cssPrefix,"-layers-counter"),...r]}})))}}}},Ha={mixout(){return{text(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{};const{transform:n=I,title:r=null,classes:a=[],attributes:o={},styles:i={}}=e;return xt({type:"text",content:t},()=>(Y("beforeDOMElementCreation",{content:t,params:e}),_e({content:t,transform:l(l({},I),n),title:r,extra:{attributes:o,styles:i,classes:["".concat(d.cssPrefix,"-layers-text"),...a]}})))}}},provides(t){t.generateLayersText=function(e,n){const{title:r,transform:a,extra:o}=n;let i=null,s=null;if(on){const f=parseInt(getComputedStyle(e).fontSize,10),c=e.getBoundingClientRect();i=c.width/f,s=c.height/f}return d.autoA11y&&!r&&(o.attributes["aria-hidden"]="true"),Promise.resolve([e,_e({content:e.innerHTML,width:i,height:s,transform:a,title:r,extra:o,watchable:!0})])}}};const Va=new RegExp('"',"ug"),Re=[1105920,1112319],Me=l(l(l(l({},{FontAwesome:{normal:"fas",400:"fas"}}),pr),Tr),Or),Yt=Object.keys(Me).reduce((t,e)=>(t[e.toLowerCase()]=Me[e],t),{}),Ga=Object.keys(Yt).reduce((t,e)=>{const n=Yt[e];return t[e]=n[900]||[...Object.entries(n)][0][1],t},{});function Ba(t){const e=t.replace(Va,""),n=Zr(e,0),r=n>=Re[0]&&n<=Re[1],a=e.length===2?e[0]===e[1]:!1;return{value:Mt(a?e[0]:e),isSecondary:r||a}}function Xa(t,e){const n=t.replace(/^['"]|['"]$/g,"").toLowerCase(),r=parseInt(e),a=isNaN(r)?"normal":r;return(Yt[n]||{})[a]||Ga[n]}function je(t,e){const n="".concat(Nr).concat(e.replace(":","-"));return new Promise((r,a)=>{if(t.getAttribute(n)!==null)return r();const i=K(t.children).filter(m=>m.getAttribute(Tt)===e)[0],s=D.getComputedStyle(t,e),f=s.getPropertyValue("font-family"),c=f.match(Lr),u=s.getPropertyValue("font-weight"),g=s.getPropertyValue("content");if(i&&!c)return t.removeChild(i),r();if(c&&g!=="none"&&g!==""){const m=s.getPropertyValue("content");let A=Xa(f,u);const{value:k,isSecondary:w}=Ba(m),v=c[0].startsWith("FontAwesome");let b=ie(A,k),x=b;if(v){const S=oa(k);S.iconName&&S.prefix&&(b=S.iconName,A=S.prefix)}if(b&&!w&&(!i||i.getAttribute(te)!==A||i.getAttribute(ee)!==x)){t.setAttribute(n,x),i&&t.removeChild(i);const S=Ma(),{extra:R}=S;R.attributes[Tt]=e,$t(b,A).then(M=>{const ot=se(l(l({},S),{},{icons:{main:M,mask:In()},prefix:A,iconName:x,extra:R,watchable:!0})),H=y.createElementNS("http://www.w3.org/2000/svg","svg");e==="::before"?t.insertBefore(H,t.firstChild):t.appendChild(H),H.outerHTML=ot.map(V=>at(V)).join(`
`),t.removeAttribute(n),r()}).catch(a)}else r()}else r()})}function qa(t){return Promise.all([je(t,"::before"),je(t,"::after")])}function Ka(t){return t.parentNode!==document.head&&!~Rr.indexOf(t.tagName.toUpperCase())&&!t.getAttribute(Tt)&&(!t.parentNode||t.parentNode.tagName!=="svg")}function Le(t){if(F)return new Promise((e,n)=>{const r=K(t.querySelectorAll("*")).filter(Ka).map(qa),a=le.begin("searchPseudoElements");Rn(),Promise.all(r).then(()=>{a(),Wt(),e()}).catch(()=>{a(),Wt(),n()})})}var Qa={hooks(){return{mutationObserverCallbacks(t){return t.pseudoElementsCallback=Le,t}}},provides(t){t.pseudoElements2svg=function(e){const{node:n=y}=e;d.searchPseudoElements&&Le(n)}}};let De=!1;var Ja={mixout(){return{dom:{unwatch(){Rn(),De=!0}}}},hooks(){return{bootstrap(){Te(Lt("mutationObserverCallbacks",{}))},noAuto(){Ta()},watch(t){const{observeMutationsRoot:e}=t;De?Wt():Te(Lt("mutationObserverCallbacks",{observeMutationsRoot:e}))}}}};const ze=t=>{let e={size:16,x:0,y:0,flipX:!1,flipY:!1,rotate:0};return t.toLowerCase().split(" ").reduce((n,r)=>{const a=r.toLowerCase().split("-"),o=a[0];let i=a.slice(1).join("-");if(o&&i==="h")return n.flipX=!0,n;if(o&&i==="v")return n.flipY=!0,n;if(i=parseFloat(i),isNaN(i))return n;switch(o){case"grow":n.size=n.size+i;break;case"shrink":n.size=n.size-i;break;case"left":n.x=n.x-i;break;case"right":n.x=n.x+i;break;case"up":n.y=n.y-i;break;case"down":n.y=n.y+i;break;case"rotate":n.rotate=n.rotate+i;break}return n},e)};var Za={mixout(){return{parse:{transform:t=>ze(t)}}},hooks(){return{parseNodeAttributes(t,e){const n=e.getAttribute("data-fa-transform");return n&&(t.transform=ze(n)),t}}},provides(t){t.generateAbstractTransformGrouping=function(e){let{main:n,transform:r,containerWidth:a,iconWidth:o}=e;const i={transform:"translate(".concat(a/2," 256)")},s="translate(".concat(r.x*32,", ").concat(r.y*32,") "),f="scale(".concat(r.size/16*(r.flipX?-1:1),", ").concat(r.size/16*(r.flipY?-1:1),") "),c="rotate(".concat(r.rotate," 0 0)"),u={transform:"".concat(s," ").concat(f," ").concat(c)},g={transform:"translate(".concat(o/2*-1," -256)")},m={outer:i,inner:u,path:g};return{tag:"g",attributes:l({},m.outer),children:[{tag:"g",attributes:l({},m.inner),children:[{tag:n.icon.tag,children:n.icon.children,attributes:l(l({},n.icon.attributes),m.path)}]}]}}}};const Pt={x:0,y:0,width:"100%",height:"100%"};function $e(t){let e=arguments.length>1&&arguments[1]!==void 0?arguments[1]:!0;return t.attributes&&(t.attributes.fill||e)&&(t.attributes.fill="black"),t}function to(t){return t.tag==="g"?t.children:[t]}var eo={hooks(){return{parseNodeAttributes(t,e){const n=e.getAttribute("data-fa-mask"),r=n?vt(n.split(" ").map(a=>a.trim())):In();return r.prefix||(r.prefix=z()),t.mask=r,t.maskId=e.getAttribute("data-fa-mask-id"),t}}},provides(t){t.generateAbstractMask=function(e){let{children:n,attributes:r,main:a,mask:o,maskId:i,transform:s}=e;const{width:f,icon:c}=a,{width:u,icon:g}=o,m=Br({transform:s,containerWidth:u,iconWidth:f}),A={tag:"rect",attributes:l(l({},Pt),{},{fill:"white"})},k=c.children?{children:c.children.map($e)}:{},w={tag:"g",attributes:l({},m.inner),children:[$e(l({tag:c.tag,attributes:l(l({},c.attributes),m.path)},k))]},v={tag:"g",attributes:l({},m.outer),children:[w]},b="mask-".concat(i||tt()),x="clip-".concat(i||tt()),S={tag:"mask",attributes:l(l({},Pt),{},{id:b,maskUnits:"userSpaceOnUse",maskContentUnits:"userSpaceOnUse"}),children:[A,v]},R={tag:"defs",children:[{tag:"clipPath",attributes:{id:x},children:to(g)},S]};return n.push(R,{tag:"rect",attributes:l({fill:"currentColor","clip-path":"url(#".concat(x,")"),mask:"url(#".concat(b,")")},Pt)}),{children:n,attributes:r}}}},no={provides(t){let e=!1;D.matchMedia&&(e=D.matchMedia("(prefers-reduced-motion: reduce)").matches),t.missingIconAbstract=function(){const n=[],r={fill:"currentColor"},a={attributeType:"XML",repeatCount:"indefinite",dur:"2s"};n.push({tag:"path",attributes:l(l({},r),{},{d:"M156.5,447.7l-12.6,29.5c-18.7-9.5-35.9-21.2-51.5-34.9l22.7-22.7C127.6,430.5,141.5,440,156.5,447.7z M40.6,272H8.5 c1.4,21.2,5.4,41.7,11.7,61.1L50,321.2C45.1,305.5,41.8,289,40.6,272z M40.6,240c1.4-18.8,5.2-37,11.1-54.1l-29.5-12.6 C14.7,194.3,10,216.7,8.5,240H40.6z M64.3,156.5c7.8-14.9,17.2-28.8,28.1-41.5L69.7,92.3c-13.7,15.6-25.5,32.8-34.9,51.5 L64.3,156.5z M397,419.6c-13.9,12-29.4,22.3-46.1,30.4l11.9,29.8c20.7-9.9,39.8-22.6,56.9-37.6L397,419.6z M115,92.4 c13.9-12,29.4-22.3,46.1-30.4l-11.9-29.8c-20.7,9.9-39.8,22.6-56.8,37.6L115,92.4z M447.7,355.5c-7.8,14.9-17.2,28.8-28.1,41.5 l22.7,22.7c13.7-15.6,25.5-32.9,34.9-51.5L447.7,355.5z M471.4,272c-1.4,18.8-5.2,37-11.1,54.1l29.5,12.6 c7.5-21.1,12.2-43.5,13.6-66.8H471.4z M321.2,462c-15.7,5-32.2,8.2-49.2,9.4v32.1c21.2-1.4,41.7-5.4,61.1-11.7L321.2,462z M240,471.4c-18.8-1.4-37-5.2-54.1-11.1l-12.6,29.5c21.1,7.5,43.5,12.2,66.8,13.6V471.4z M462,190.8c5,15.7,8.2,32.2,9.4,49.2h32.1 c-1.4-21.2-5.4-41.7-11.7-61.1L462,190.8z M92.4,397c-12-13.9-22.3-29.4-30.4-46.1l-29.8,11.9c9.9,20.7,22.6,39.8,37.6,56.9 L92.4,397z M272,40.6c18.8,1.4,36.9,5.2,54.1,11.1l12.6-29.5C317.7,14.7,295.3,10,272,8.5V40.6z M190.8,50 c15.7-5,32.2-8.2,49.2-9.4V8.5c-21.2,1.4-41.7,5.4-61.1,11.7L190.8,50z M442.3,92.3L419.6,115c12,13.9,22.3,29.4,30.5,46.1 l29.8-11.9C470,128.5,457.3,109.4,442.3,92.3z M397,92.4l22.7-22.7c-15.6-13.7-32.8-25.5-51.5-34.9l-12.6,29.5 C370.4,72.1,384.4,81.5,397,92.4z"})});const o=l(l({},a),{},{attributeName:"opacity"}),i={tag:"circle",attributes:l(l({},r),{},{cx:"256",cy:"364",r:"28"}),children:[]};return e||i.children.push({tag:"animate",attributes:l(l({},a),{},{attributeName:"r",values:"28;14;28;28;14;28;"})},{tag:"animate",attributes:l(l({},o),{},{values:"1;0;1;1;0;1;"})}),n.push(i),n.push({tag:"path",attributes:l(l({},r),{},{opacity:"1",d:"M263.7,312h-16c-6.6,0-12-5.4-12-12c0-71,77.4-63.9,77.4-107.8c0-20-17.8-40.2-57.4-40.2c-29.1,0-44.3,9.6-59.2,28.7 c-3.9,5-11.1,6-16.2,2.4l-13.1-9.2c-5.6-3.9-6.9-11.8-2.6-17.2c21.2-27.2,46.4-44.7,91.2-44.7c52.3,0,97.4,29.8,97.4,80.2 c0,67.6-77.4,63.5-77.4,107.8C275.7,306.6,270.3,312,263.7,312z"}),children:e?[]:[{tag:"animate",attributes:l(l({},o),{},{values:"1;0;0;0;0;1;"})}]}),e||n.push({tag:"path",attributes:l(l({},r),{},{opacity:"0",d:"M232.5,134.5l7,168c0.3,6.4,5.6,11.5,12,11.5h9c6.4,0,11.7-5.1,12-11.5l7-168c0.3-6.8-5.2-12.5-12-12.5h-23 C237.7,122,232.2,127.7,232.5,134.5z"}),children:[{tag:"animate",attributes:l(l({},o),{},{values:"0;0;1;1;0;0;"})}]}),{tag:"g",attributes:{class:"missing"},children:n}}}},ro={hooks(){return{parseNodeAttributes(t,e){const n=e.getAttribute("data-fa-symbol"),r=n===null?!1:n===""?!0:n;return t.symbol=r,t}}}},ao=[Kr,Ua,Wa,Ya,Ha,Qa,Ja,Za,eo,no,ro];pa(ao,{mixoutsTo:_});_.noAuto;_.config;_.library;_.dom;const Ht=_.parse;_.findIconDefinition;_.toHtml;const oo=_.icon;_.layer;_.text;_.counter;var jn={exports:{}},io="SECRET_DO_NOT_PASS_THIS_OR_YOU_WILL_BE_FIRED",so=io,lo=so;function Ln(){}function Dn(){}Dn.resetWarningCache=Ln;var fo=function(){function t(r,a,o,i,s,f){if(f!==lo){var c=new Error("Calling PropTypes validators directly is not supported by the `prop-types` package. Use PropTypes.checkPropTypes() to call them. Read more at http://fb.me/use-check-prop-types");throw c.name="Invariant Violation",c}}t.isRequired=t;function e(){return t}var n={array:t,bigint:t,bool:t,func:t,number:t,object:t,string:t,symbol:t,any:t,arrayOf:e,element:t,elementType:t,instanceOf:e,node:t,objectOf:e,oneOf:e,oneOfType:e,shape:e,exact:e,checkPropTypes:Dn,resetWarningCache:Ln};return n.PropTypes=n,n};jn.exports=fo();var co=jn.exports;const p=Ve(co);var uo={};function Vt(t,e){(e==null||e>t.length)&&(e=t.length);for(var n=0,r=Array(e);n<e;n++)r[n]=t[n];return r}function mo(t){if(Array.isArray(t))return t}function po(t){if(Array.isArray(t))return Vt(t)}function L(t,e,n){return(e=wo(e))in t?Object.defineProperty(t,e,{value:n,enumerable:!0,configurable:!0,writable:!0}):t[e]=n,t}function go(t){if(typeof Symbol<"u"&&t[Symbol.iterator]!=null||t["@@iterator"]!=null)return Array.from(t)}function ho(t,e){var n=t==null?null:typeof Symbol<"u"&&t[Symbol.iterator]||t["@@iterator"];if(n!=null){var r,a,o,i,s=[],f=!0,c=!1;try{if(o=(n=n.call(t)).next,e!==0)for(;!(f=(r=o.call(n)).done)&&(s.push(r.value),s.length!==e);f=!0);}catch(u){c=!0,a=u}finally{try{if(!f&&n.return!=null&&(i=n.return(),Object(i)!==i))return}finally{if(c)throw a}}return s}}function yo(){throw new TypeError(`Invalid attempt to destructure non-iterable instance.
In order to be iterable, non-array objects must have a [Symbol.iterator]() method.`)}function bo(){throw new TypeError(`Invalid attempt to spread non-iterable instance.
In order to be iterable, non-array objects must have a [Symbol.iterator]() method.`)}function Ue(t,e){var n=Object.keys(t);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(t);e&&(r=r.filter(function(a){return Object.getOwnPropertyDescriptor(t,a).enumerable})),n.push.apply(n,r)}return n}function E(t){for(var e=1;e<arguments.length;e++){var n=arguments[e]!=null?arguments[e]:{};e%2?Ue(Object(n),!0).forEach(function(r){L(t,r,n[r])}):Object.getOwnPropertyDescriptors?Object.defineProperties(t,Object.getOwnPropertyDescriptors(n)):Ue(Object(n)).forEach(function(r){Object.defineProperty(t,r,Object.getOwnPropertyDescriptor(n,r))})}return t}function vo(t,e){if(t==null)return{};var n,r,a=xo(t,e);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(t);for(r=0;r<o.length;r++)n=o[r],e.indexOf(n)===-1&&{}.propertyIsEnumerable.call(t,n)&&(a[n]=t[n])}return a}function xo(t,e){if(t==null)return{};var n={};for(var r in t)if({}.hasOwnProperty.call(t,r)){if(e.indexOf(r)!==-1)continue;n[r]=t[r]}return n}function We(t,e){return mo(t)||ho(t,e)||zn(t,e)||yo()}function Gt(t){return po(t)||go(t)||zn(t)||bo()}function Ao(t,e){if(typeof t!="object"||!t)return t;var n=t[Symbol.toPrimitive];if(n!==void 0){var r=n.call(t,e);if(typeof r!="object")return r;throw new TypeError("@@toPrimitive must return a primitive value.")}return(e==="string"?String:Number)(t)}function wo(t){var e=Ao(t,"string");return typeof e=="symbol"?e:e+""}function gt(t){"@babel/helpers - typeof";return gt=typeof Symbol=="function"&&typeof Symbol.iterator=="symbol"?function(e){return typeof e}:function(e){return e&&typeof Symbol=="function"&&e.constructor===Symbol&&e!==Symbol.prototype?"symbol":typeof e},gt(t)}function zn(t,e){if(t){if(typeof t=="string")return Vt(t,e);var n={}.toString.call(t).slice(8,-1);return n==="Object"&&t.constructor&&(n=t.constructor.name),n==="Map"||n==="Set"?Array.from(t):n==="Arguments"||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)?Vt(t,e):void 0}}var So="7.0.0",Bt;try{var Oo=require("@fortawesome/fontawesome-svg-core/package.json");Bt=Oo.version}catch{Bt=typeof process<"u"&&uo.FA_VERSION||"7.0.0"}function ko(t){var e=t.beat,n=t.fade,r=t.beatFade,a=t.bounce,o=t.shake,i=t.flash,s=t.spin,f=t.spinPulse,c=t.spinReverse,u=t.pulse,g=t.fixedWidth,m=t.inverse,A=t.border,k=t.listItem,w=t.flip,v=t.size,b=t.rotation,x=t.pull,S=t.swapOpacity,R=t.rotateBy,M=t.widthAuto,ot=Po(Bt,So),H=L(L(L(L(L(L({"fa-beat":e,"fa-fade":n,"fa-beat-fade":r,"fa-bounce":a,"fa-shake":o,"fa-flash":i,"fa-spin":s,"fa-spin-reverse":c,"fa-spin-pulse":f,"fa-pulse":u,"fa-fw":g,"fa-inverse":m,"fa-border":A,"fa-li":k,"fa-flip":w===!0,"fa-flip-horizontal":w==="horizontal"||w==="both","fa-flip-vertical":w==="vertical"||w==="both"},"fa-".concat(v),typeof v<"u"&&v!==null),"fa-rotate-".concat(b),typeof b<"u"&&b!==null&&b!==0),"fa-pull-".concat(x),typeof x<"u"&&x!==null),"fa-swap-opacity",S),"fa-rotate-by",ot&&R),"fa-width-auto",ot&&M);return Object.keys(H).map(function(V){return H[V]?V:null}).filter(function(V){return V})}function Po(t,e){for(var n=t.split("-"),r=We(n,2),a=r[0],o=r[1],i=e.split("-"),s=We(i,2),f=s[0],c=s[1],u=a.split("."),g=f.split("."),m=0;m<Math.max(u.length,g.length);m++){var A=u[m]||"0",k=g[m]||"0",w=parseInt(A,10),v=parseInt(k,10);if(w!==v)return w>v}for(var b=0;b<Math.max(u.length,g.length);b++){var x=u[b]||"0",S=g[b]||"0";if(x!==S&&x.length!==S.length)return x.length<S.length}return!(o&&!c)}function _o(t){return t=t-0,t===t}function $n(t){return _o(t)?t:(t=t.replace(/[\-_\s]+(.)?/g,function(e,n){return n?n.toUpperCase():""}),t.substr(0,1).toLowerCase()+t.substr(1))}var Eo=["style"];function Io(t){return t.charAt(0).toUpperCase()+t.slice(1)}function Co(t){return t.split(";").map(function(e){return e.trim()}).filter(function(e){return e}).reduce(function(e,n){var r=n.indexOf(":"),a=$n(n.slice(0,r)),o=n.slice(r+1).trim();return a.startsWith("webkit")?e[Io(a)]=o:e[a]=o,e},{})}function Un(t,e){var n=arguments.length>2&&arguments[2]!==void 0?arguments[2]:{};if(typeof e=="string")return e;var r=(e.children||[]).map(function(f){return Un(t,f)}),a=Object.keys(e.attributes||{}).reduce(function(f,c){var u=e.attributes[c];switch(c){case"class":f.attrs.className=u,delete e.attributes.class;break;case"style":f.attrs.style=Co(u);break;default:c.indexOf("aria-")===0||c.indexOf("data-")===0?f.attrs[c.toLowerCase()]=u:f.attrs[$n(c)]=u}return f},{attrs:{}}),o=n.style,i=o===void 0?{}:o,s=vo(n,Eo);return a.attrs.style=E(E({},a.attrs.style),i),t.apply(void 0,[e.tag,E(E({},a.attrs),s)].concat(Gt(r)))}var Wn=!1;try{Wn=!0}catch{}function To(){if(!Wn&&console&&typeof console.error=="function"){var t;(t=console).error.apply(t,arguments)}}function Ye(t){if(t&&gt(t)==="object"&&t.prefix&&t.iconName&&t.icon)return t;if(Ht.icon)return Ht.icon(t);if(t===null)return null;if(t&&gt(t)==="object"&&t.prefix&&t.iconName)return t;if(Array.isArray(t)&&t.length===2)return{prefix:t[0],iconName:t[1]};if(typeof t=="string")return{prefix:"fas",iconName:t}}function _t(t,e){return Array.isArray(e)&&e.length>0||!Array.isArray(e)&&e?L({},t,e):{}}var He={border:!1,className:"",mask:null,maskId:null,fixedWidth:!1,inverse:!1,flip:!1,icon:null,listItem:!1,pull:null,pulse:!1,rotation:null,rotateBy:!1,size:null,spin:!1,spinPulse:!1,spinReverse:!1,beat:!1,fade:!1,beatFade:!1,bounce:!1,shake:!1,symbol:!1,title:"",titleId:null,transform:null,swapOpacity:!1,widthAuto:!1},ce=Jt.forwardRef(function(t,e){var n=E(E({},He),t),r=n.icon,a=n.mask,o=n.symbol,i=n.className,s=n.title,f=n.titleId,c=n.maskId,u=Ye(r),g=_t("classes",[].concat(Gt(ko(n)),Gt((i||"").split(" ")))),m=_t("transform",typeof n.transform=="string"?Ht.transform(n.transform):n.transform),A=_t("mask",Ye(a)),k=oo(u,E(E(E(E({},g),m),A),{},{symbol:o,title:s,titleId:f,maskId:c}));if(!k)return To("Could not find icon",u),null;var w=k.abstract,v={ref:e};return Object.keys(n).forEach(function(b){He.hasOwnProperty(b)||(v[b]=n[b])}),No(w[0],v)});ce.displayName="FontAwesomeIcon";ce.propTypes={beat:p.bool,border:p.bool,beatFade:p.bool,bounce:p.bool,className:p.string,fade:p.bool,flash:p.bool,mask:p.oneOfType([p.object,p.array,p.string]),maskId:p.string,fixedWidth:p.bool,inverse:p.bool,flip:p.oneOf([!0,!1,"horizontal","vertical","both"]),icon:p.oneOfType([p.object,p.array,p.string]),listItem:p.bool,pull:p.oneOf(["right","left"]),pulse:p.bool,rotation:p.oneOf([0,90,180,270]),rotateBy:p.bool,shake:p.bool,size:p.oneOf(["2xs","xs","sm","lg","xl","2xl","1x","2x","3x","4x","5x","6x","7x","8x","9x","10x"]),spin:p.bool,spinPulse:p.bool,spinReverse:p.bool,symbol:p.oneOfType([p.bool,p.string]),title:p.string,titleId:p.string,transform:p.oneOfType([p.string,p.object]),swapOpacity:p.bool,widthAuto:p.bool};var No=Un.bind(null,Jt.createElement);const Mo=Object.freeze(Object.defineProperty({__proto__:null,FontAwesomeIcon:ce},Symbol.toStringTag,{value:"Module"}));export{Ro as R,Jt as a,Fo as c,Ve as g,Mo as i,en as r};
