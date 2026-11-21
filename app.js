(() => {
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const desktop=$("#desktop"), control=$("#controlPanel"), launcher=$("#launcher"), win=$("#appWindow"), title=$("#windowTitle"), content=$("#windowContent"), toast=$("#toast");
let activeApp=null, toastTimer, maximized=false;
const appNames={files:"Files",browser:"Browser",notes:"Notes",terminal:"Terminal",gaming:"Gaming Hub",monitor:"System Monitor",settings:"Settings",calculator:"Calculator"};
function clock(){const d=new Date();$("#clock").textContent=d.toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"})}
clock();setInterval(clock,30000);
function notify(msg){toast.textContent=msg;toast.classList.remove("hidden");clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.add("hidden"),2200)}
function closePanels(){control.classList.add("hidden");launcher.classList.add("hidden")}
$("#controlButton").onclick=()=>{launcher.classList.add("hidden");control.classList.toggle("hidden")};
$("#notificationButton").onclick=()=>{launcher.classList.add("hidden");control.classList.remove("hidden");control.scrollIntoView({block:"nearest"})};
$("#launcherButton").onclick=()=>{control.classList.add("hidden");launcher.classList.toggle("hidden");$("#appSearch").focus()};
$$("[data-close]").forEach(b=>b.onclick=()=>$("#"+b.dataset.close).classList.add("hidden"));
$$("[data-toggle]").forEach(b=>b.onclick=()=>{b.classList.toggle("active");notify(b.querySelector("b").textContent+" toggled (prototype)")});
$("#brightness").oninput=e=>desktop.style.filter="brightness("+e.target.value/100+")";
$("#volume").oninput=e=>notify("Volume level: "+e.target.value+"% (visual prototype)");
$$("[data-app]").forEach(b=>b.addEventListener("click",()=>openApp(b.dataset.app)));
function openApp(app){if(!appNames[app])return;activeApp=app;closePanels();launcher.classList.add("hidden");win.classList.remove("hidden");win.classList.remove("maximized");maximized=false;title.textContent=appNames[app];content.innerHTML=appView(app);wireApp(app)}
function appView(app){
const heading=(t,s)=>'<h2 class="content-title">'+t+'</h2><p class="content-sub">'+s+'</p>';
if(app==="files")return heading("Files","A simple workspace preview.")+'<div class=card-grid><div class=content-card><h3>Home</h3><p>Personal files and folders</p></div><div class=content-card><h3>Documents</h3><p>Saved documents</p></div><div class=content-card><h3>Downloads</h3><p>Downloaded items</p></div><div class=content-card><h3>Pictures</h3><p>Images and wallpapers</p></div></div><p class=content-sub style=margin-top:20px>This is a mock file browser. It does not access your computer’s files yet.</p>';
if(app==="notes")return heading("Notes","Your notes are saved locally in this browser.")+'<textarea class="note-area" id="notesText" placeholder="Write something…"></textarea><div style="display:flex;justify-content:space-between;margin-top:10px"><small class=content-sub id=notesStatus>Autosave ready</small><button class=action-button id=clearNotes>Clear note</button></div>';
if(app==="settings")return heading("Personalisation","Adjust your desktop look.")+'<div class=setting-row><span>Accent colour</span><select id=accentSelect><option value="#8b7cff">Violet</option><option value="#44c9e8">Cyan</option><option value="#5ed3a3">Emerald</option><option value="#e7a56d">Amber</option><option value="#ee82b6">Rose</option></select></div><div class=setting-row><span>Glass blur</span><input id=blurSelect type=range min=0 max=30 value=20></div><div class=setting-row><span>Reduce motion</span><button class=action-button id=motionToggle>Toggle</button></div><div class=setting-row><span>Lightweight mode</span><button class=action-button id=lightToggle>Toggle</button></div><div class=content-card style=margin-top:18px><h3>Privacy note</h3><p>Settings are local UI preferences. This prototype has no OS-level privileges.</p></div>';
if(app==="gaming")return heading("Gaming Hub","Discover your games and tune the experience.")+'<div class=card-grid><div class=content-card><h3>Steam</h3><p>Native Steam support is planned for the Linux-based future. This browser demo cannot launch Steam.</p></div><div class=content-card><h3>Performance</h3><p>Lightweight mode and reduced effects are available in Settings.</p></div><div class=content-card><h3>Controller</h3><p>Controller setup is a planned system feature.</p></div></div>';
if(app==="monitor")return heading("System Monitor","Prototype metrics, not real hardware telemetry.")+'<div class=card-grid><div class=content-card><h3>Memory</h3><p>Demo meter — no actual RAM data is being read.</p><div style="height:8px;background:#333;border-radius:10px;margin-top:12px"><div style="height:8px;width:42%;background:var(--accent);border-radius:10px"></div></div></div><div class=content-card><h3>Storage</h3><p>Demo meter — storage usage is not connected.</p></div><div class=content-card><h3>CPU</h3><p>Telemetry integration planned for native Linux backend.</p></div></div>';
if(app==="browser")return heading("Browser","Safe browser interface mockup.")+'<div class=browser-address><input id=browserUrl value="https://example.com" aria-label="URL"><button class=action-button id=browserGo>Open</button></div><div class=content-card style=margin-top:14px><h3>Browser preview</h3><p class=content-sub id=browserMsg>External pages are not loaded inside this demo. Use Open to visit a site in a new tab.</p></div>';
if(app==="terminal")return heading("Terminal","Command interface simulation. Commands do not execute on your computer.")+'<div class=terminal-box id=terminalOut>NEXUS Terminal Prototype v0.1\nSafe simulation — no system commands are executed.\nType help to see available demo commands.</div><div class=terminal-input><input id=terminalInput placeholder="Type a demo command…"><button class=action-button id=terminalSend>Run</button></div>';
if(app==="calculator")return heading("Calculator","Basic calculator.")+'<div class=calc><input id=calcDisplay class=calc-display readonly value="0" readonly><div class=calc-buttons>'+["7","8","9","÷","4","5","6","×","1","2","3","−","C","0",".","+","="].map(k=>'<button data-calc="'+k+'">'+k+'</button>').join("")+'</div></div>';
return heading(appNames[app],"Application preview");
}
function wireApp(app){
if(app==="notes"){const n=$("#notesText");n.value=localStorage.getItem("nexus-note")||"";n.oninput=()=>{localStorage.setItem("nexus-note",n.value);$("#notesStatus").textContent="Saved locally"};$("#clearNotes").onclick=()=>{n.value="";localStorage.removeItem("nexus-note");$("#notesStatus").textContent="Cleared"}}
if(app==="settings"){$("#accentSelect").onchange=e=>{document.documentElement.style.setProperty("--accent",e.target.value);localStorage.setItem("nexus-accent",e.target.value)};$("#blurSelect").oninput=e=>{document.documentElement.style.setProperty("--blur",e.target.value+"px");localStorage.setItem("nexus-blur",e.target.value)};$("#motionToggle").onclick=()=>{document.body.classList.toggle("reduced-motion");notify("Motion preference toggled (prototype)")};$("#lightToggle").onclick=()=>{desktop.classList.toggle("lightweight");document.documentElement.style.setProperty("--blur",desktop.classList.contains("lightweight")?"3px":"20px");notify("Lightweight mode toggled")}}
if(app==="browser")$("#browserGo").onclick=()=>{let url=$("#browserUrl").value.trim();if(!/^https?:\/\//i.test(url))url="https://"+url;try{const u=new URL(url);if(!["http:","https:"].includes(u.protocol))throw 0;window.open(u.href,"_blank","noopener");$("#browserMsg").textContent="Opened external site in a new tab."}catch{$("#browserMsg").textContent="Please enter a valid HTTP or HTTPS address."}};
if(app==="terminal"){const run=()=>{const inp=$("#terminalInput"),out=$("#terminalOut"),cmd=inp.value.trim().toLowerCase();const responses={help:"Demo commands: help, date, clear, about, apps, status",date:new Date().toString(),about:"NEXUS OS desktop prototype. No shell access.",apps:"Files, Browser, Notes, Terminal, Gaming Hub, System Monitor, Settings, Calculator",status:"Prototype status: UI active. System telemetry unavailable."};if(cmd==="clear")out.textContent="";else out.textContent+="\n> "+cmd+"\n"+(responses[cmd]||"Unknown demo command. Try help.");inp.value="";out.scrollTop=out.scrollHeight};$("#terminalSend").onclick=run;$("#terminalInput").onkeydown=e=>{if(e.key==="Enter")run()}}
if(app==="calculator"){
 let exp="";
 const display=$("#calcDisplay");
 function evaluateExpression(input){
  const tokens=input.match(/\\d+(?:\\.\\d+)?|[()+\\-*/]/g)||[];
  if(tokens.join("")!==input.replace(/\\s/g,""))throw Error("Invalid expression");
  let pos=0;
  function primary(){
   const t=tokens[pos++];
   if(t==="("){const v=addSub();if(tokens[pos++]!==")")throw Error("Missing )");return v}
   if(t==="+"||t==="-"){const v=primary();return t==="-"?-v:v}
   if(!t||!/^\\d+(?:\\.\\d+)?$/.test(t))throw Error("Expected number");
   return Number(t);
  }
  function mulDiv(){let v=primary();while(tokens[pos]==="*"||tokens[pos]==="/"){const op=tokens[pos++],rhs=primary();if(op==="/"&&rhs===0)throw Error("Division by zero");v=op==="*"?v*rhs:v/rhs}return v}
  function addSub(){let v=mulDiv();while(tokens[pos]==="+"||tokens[pos]==="-"){const op=tokens[pos++],rhs=mulDiv();v=op==="+"?v+rhs:v-rhs}return v}
  const result=addSub();if(pos!==tokens.length||!Number.isFinite(result))throw Error("Invalid result");return result;
 }
 $("[data-calc]").forEach(b=>b.onclick=()=>{
  const k=b.dataset.calc;
  if(k==="C"){exp="";display.value="0"}
  else if(k==="="){try{display.value=String(evaluateExpression(exp));exp=display.value}catch{display.value="Error";exp=""}}
  else{exp+=({"÷":"/","×":"*","−":"-"}[k]||k);display.value=exp}
 });
}
}
// Basic desktop window manager: drag, focus, and edge snap.
let zCounter=10;
function focusWindow(){win.style.zIndex=String(++zCounter)}
win.addEventListener("pointerdown",focusWindow);
const titlebar=win.querySelector(".window-titlebar");
let dragging=null;
titlebar.addEventListener("pointerdown",e=>{
 if(e.target.closest(".window-control"))return;
 if(maximized){maximized=false;win.classList.remove("maximized");win.style.left=e.clientX+"px";win.style.top=e.clientY+"px";win.style.transform="none";}
 const r=win.getBoundingClientRect();
 dragging={dx:e.clientX-r.left,dy:e.clientY-r.top};
 titlebar.setPointerCapture(e.pointerId);
});
titlebar.addEventListener("pointermove",e=>{
 if(!dragging)return;
 const w=win.offsetWidth,h=win.offsetHeight;
 const left=Math.max(0,Math.min(innerWidth-w,e.clientX-dragging.dx));
 const top=Math.max(56,Math.min(innerHeight-h-65,e.clientY-dragging.dy));
 win.style.left=left+"px";win.style.top=top+"px";win.style.transform="none";
});
titlebar.addEventListener("pointerup",e=>{
 if(!dragging)return;dragging=null;
 const x=e.clientX;
 if(x<=12){win.style.left="8px";win.style.top="60px";win.style.width="calc(50vw - 12px)";win.style.height="calc(100vh - 90px)";win.style.transform="none";win.classList.add("snapped-left")}
 else if(x>=innerWidth-12){win.style.left="calc(50vw + 4px)";win.style.top="60px";win.style.width="calc(50vw - 12px)";win.style.height="calc(100vh - 90px)";win.style.transform="none";win.classList.add("snapped-right")}
 else win.classList.remove("snapped-left","snapped-right");
});
titlebar.addEventListener("dblclick",e=>{if(e.target.closest(".window-control"))return;maximized=!maximized;win.classList.toggle("maximized",maximized);win.style.left="";win.style.top="";win.style.width="";win.style.height="";win.style.transform="";win.classList.remove("snapped-left","snapped-right")});
\n$("#windowClose").onclick=()=>win.classList.add("hidden");$("#windowMin").onclick=()=>win.classList.add("hidden");$("#windowMax").onclick=()=>{maximized=!maximized;win.classList.toggle("maximized",maximized)};
$("#appSearch").oninput=e=>{const term=e.target.value.toLowerCase();$$(".app-item").forEach(item=>item.style.display=item.textContent.toLowerCase().includes(term)?"flex":"none")};
$$(".app-item").forEach(item=>item.onclick=()=>openApp(item.dataset.app));
const savedAccent=localStorage.getItem("nexus-accent");if(savedAccent)document.documentElement.style.setProperty("--accent",savedAccent);const savedBlur=localStorage.getItem("nexus-blur");if(savedBlur)document.documentElement.style.setProperty("--blur",savedBlur+"px");
})();