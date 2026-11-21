(() => {
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const desktop=$("#desktop"), control=$("#controlPanel"), launcher=$("#launcher"), win=$("#appWindow"), title=$("#windowTitle"), content=$("#windowContent"), toast=$("#toast");
const wallpaperCatalog={
 "mountain-night":"https://images.unsplash.com/photo-1725663656850-7bc515816fcd?auto=format&fit=crop&w=2400&q=85",
 "alpine":"https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=2400&q=85",
 "forest":"https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=2400&q=85",
 "cosmos":"https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=2400&q=85",
 "city":"https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&fit=crop&w=2400&q=85",
 "modern":"https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=2400&q=85"
};
function setDesktopWallpaper(id,persist=true){
 const image=wallpaperCatalog[id];if(!image)return false;
 desktop.style.backgroundImage='linear-gradient(120deg,rgba(8,13,25,.72),rgba(11,13,30,.24)),url("'+image+'")';
 if(persist)localStorage.setItem("nexus-wallpaper",id);
 return true;
}
let activeApp=null, toastTimer, maximized=false;
const appNames={files:"Files",browser:"Browser",notes:"Notes",terminal:"Terminal",gaming:"Gaming Hub",monitor:"System Monitor",settings:"Settings",calculator:"Calculator"};
function clock(){const d=new Date();$("#clock").textContent=d.toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"})}
clock();setInterval(clock,30000);
function notify(msg){toast.textContent=msg;toast.classList.remove("hidden");clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.add("hidden"),2200)}
function closePanels(){control.classList.add("hidden");launcher.classList.add("hidden")}
$("#controlButton").onclick=()=>{launcher.classList.add("hidden");control.classList.toggle("hidden")};
$("#notificationButton").onclick=()=>{launcher.classList.add("hidden");control.classList.remove("hidden");$("#controlNotifications").scrollIntoView({block:"nearest",behavior:document.body.classList.contains("reduced-motion")?"auto":"smooth"})};
$("#clearNotifications").onclick=()=>{$("#notificationList").innerHTML='<div class="notification-empty"><p>You are all caught up.</p><small>Notifications will appear here.</small></div>';notify("Notifications cleared")};
$("#launcherButton").onclick=()=>{control.classList.add("hidden");launcher.classList.toggle("hidden");$("#appSearch").focus()};
$("[data-close]").forEach(b=>b.onclick=()=>$("#"+b.dataset.close).classList.add("hidden"));
document.addEventListener("keydown",e=>{if(e.key==="Escape"){control.classList.add("hidden");launcher.classList.add("hidden")}});
const controlDefaults={wifi:true,bluetooth:false,dnd:false,power:false};
const controlState={...controlDefaults};
function applyControlToggle(button, enabled){
 const key=button.dataset.toggle;
 controlState[key]=enabled;
 button.classList.toggle("active",enabled);
 button.setAttribute("aria-pressed",String(enabled));
 const stateLabel=enabled?"On":"Off";
 button.querySelector("small").textContent=stateLabel+" · preview";
 localStorage.setItem("nexus-control-"+key,String(enabled));
 if(key==="power")desktop.classList.toggle("lightweight",enabled);
}
function setControlPreference(key,enabled){
 const button=$('[data-toggle="'+key+'"]');
 if(button)applyControlToggle(button,enabled);
}
$("[data-toggle]").forEach(button=>{
 const key=button.dataset.toggle;
 const saved=localStorage.getItem("nexus-control-"+key);
 applyControlToggle(button,saved===null?controlDefaults[key]:saved==="true");
 button.onclick=()=>applyControlToggle(button,!controlState[key]);
});
const brightness=$("#brightness"),volume=$("#volume");
const savedBrightness=localStorage.getItem("nexus-brightness");
const savedVolume=localStorage.getItem("nexus-volume");
if(savedBrightness!==null)brightness.value=savedBrightness;
if(savedVolume!==null)volume.value=savedVolume;
function updateSlider(input,output,key){
 output.value=input.value+"%";
 output.textContent=input.value+"%";
 localStorage.setItem(key,input.value);
}
function updateBrightness(){
 updateSlider(brightness,$("#brightnessValue"),"nexus-brightness");
 desktop.style.filter="brightness("+Number(brightness.value)/100+")";
}
function updateVolume(){
 updateSlider(volume,$("#volumeValue"),"nexus-volume");
}
brightness.oninput=updateBrightness;
volume.oninput=updateVolume;
updateBrightness();
updateVolume();
$$("[data-app]").forEach(b=>b.addEventListener("click",()=>{
 const app=b.dataset.app;
 if(b.classList.contains("dock-app")&&activeApp===app){
  if(win.classList.contains("hidden")){win.classList.remove("hidden");$(".dock-app[data-app='"+app+"']")?.classList.remove("minimized");focusWindow()}
  else focusWindow();
  closePanels();
  return;
 }
 openApp(app);
}));
function openApp(app){if(!appNames[app])return;activeApp=app;closePanels();launcher.classList.add("hidden");win.classList.remove("hidden");win.classList.remove("maximized");maximized=false;title.textContent=appNames[app];content.innerHTML=appView(app);wireApp(app);$( ".dock-app[data-app]" ).forEach(b=>{b.classList.toggle("running",b.dataset.app===app);b.classList.remove("minimized")});focusWindow()}
function appView(app){
const heading=(t,s)=>'<h2 class="content-title">'+t+'</h2><p class="content-sub">'+s+'</p>';
if(app==="files")return heading("Files","A simple workspace preview.")+'<div class=card-grid><div class=content-card><h3>Home</h3><p>Personal files and folders</p></div><div class=content-card><h3>Documents</h3><p>Saved documents</p></div><div class=content-card><h3>Downloads</h3><p>Downloaded items</p></div><div class=content-card><h3>Pictures</h3><p>Images and wallpapers</p></div></div><p class=content-sub style=margin-top:20px>This is a mock file browser. It does not access your computer’s files yet.</p>';
if(app==="notes")return heading("Notes","Your notes are saved locally in this browser.")+'<textarea class="note-area" id="notesText" placeholder="Write something…"></textarea><div style="display:flex;justify-content:space-between;margin-top:10px"><small class=content-sub id=notesStatus>Autosave ready</small><button class=action-button id=clearNotes>Clear note</button></div>';
if(app==="settings")return '<div class="settings-layout"><aside class="settings-sidebar" aria-label="Settings categories"><p class="settings-kicker">PREFERENCES</p><button class="settings-nav active" data-settings-section="appearance"><span>◐</span> Appearance</button><button class="settings-nav" data-settings-section="performance"><span>ϟ</span> Performance</button><button class="settings-nav" data-settings-section="notifications"><span>◉</span> Notifications</button><button class="settings-nav" data-settings-section="accessibility"><span>◎</span> Accessibility</button><button class="settings-nav" data-settings-section="system"><span>⌘</span> System</button></aside><div class="settings-main"><section class="settings-page" data-settings-page="appearance">'+heading("Appearance","Make NEXUS feel like your own.")+'<div class="settings-card"><div class="settings-card-heading"><h3>Desktop theme</h3><p>Choose the overall look of your workspace.</p></div><div class="theme-options"><button class="theme-choice" data-theme-choice="dark" type="button">Dark</button><button class="theme-choice" data-theme-choice="light" type="button">Light</button><button class="theme-choice" data-theme-choice="system" type="button">System</button></div><p class="settings-hint" id="themeStatus">Dark theme selected.</p></div><div class="settings-card"><div class="settings-card-heading"><h3>Accent colour</h3><p>Choose the highlight used across the interface.</p></div><div class="accent-options"><button class="accent-swatch" data-accent="#ffad7a" aria-label="Copper accent" title="Copper"></button><button class="accent-swatch" data-accent="#8b7cff" aria-label="Violet accent" title="Violet"></button><button class="accent-swatch" data-accent="#44c9e8" aria-label="Cyan accent" title="Cyan"></button><button class="accent-swatch" data-accent="#5ed3a3" aria-label="Emerald accent" title="Emerald"></button><button class="accent-swatch" data-accent="#ee82b6" aria-label="Rose accent" title="Rose"></button></div><p class="settings-hint" id="accentStatus">Copper is the default NEXUS accent.</p></div><div class="settings-card wallpaper-card"><div class="settings-card-heading"><h3>Desktop wallpaper</h3><p>Choose a photographic background for your workspace. Images are served by Unsplash.</p></div><div class="wallpaper-filters" role="group" aria-label="Wallpaper categories"><button class="wallpaper-filter active" data-wallpaper-filter="all" type="button">All</button><button class="wallpaper-filter" data-wallpaper-filter="nature" type="button">Nature</button><button class="wallpaper-filter" data-wallpaper-filter="space" type="button">Space</button><button class="wallpaper-filter" data-wallpaper-filter="architecture" type="button">Architecture</button></div><div class="wallpaper-grid" id="wallpaperGrid"><button class="wallpaper-option" type="button" data-wallpaper="mountain-night" data-category="nature" aria-label="Apply mountain night wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1725663656850-7bc515816fcd?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Starry sky above a mountain range"><span>Mountain Night</span></button><button class="wallpaper-option" type="button" data-wallpaper="alpine" data-category="nature" aria-label="Apply alpine landscape wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Dramatic alpine mountain peaks"><span>Alpine</span></button><button class="wallpaper-option" type="button" data-wallpaper="forest" data-category="nature" aria-label="Apply forest wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Sunlight through a green forest"><span>Forest</span></button><button class="wallpaper-option" type="button" data-wallpaper="cosmos" data-category="space" aria-label="Apply cosmos wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Colourful deep space nebula"><span>Cosmos</span></button><button class="wallpaper-option" type="button" data-wallpaper="city" data-category="architecture" aria-label="Apply city wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="City skyline at dusk"><span>City Lights</span></button><button class="wallpaper-option" type="button" data-wallpaper="modern" data-category="architecture" aria-label="Apply architecture wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Modern architectural structure"><span>Architecture</span></button></div><div class="wallpaper-footer"><p class="settings-hint" id="wallpaperStatus">Choose a wallpaper to see a larger preview before applying it.</p><a href="https://unsplash.com/license" target="_blank" rel="noopener noreferrer">Unsplash licence</a></div><dialog class="wallpaper-preview-dialog" id="wallpaperPreviewDialog" aria-labelledby="wallpaperPreviewTitle"><div class="wallpaper-preview-shell"><div class="wallpaper-preview-heading"><div><p class="settings-kicker">DESKTOP PREVIEW</p><h3 id="wallpaperPreviewTitle">Wallpaper preview</h3></div><button class="preview-close" type="button" data-preview-close aria-label="Close preview">×</button></div><img id="wallpaperPreviewImage" class="wallpaper-preview-image" alt="Large preview of the selected wallpaper"><p class="wallpaper-preview-caption" id="wallpaperPreviewCaption">This will become your desktop background.</p><div class="wallpaper-preview-actions"><button class="action-button preview-cancel" type="button" data-preview-close>Cancel</button><button class="action-button preview-apply" id="applyWallpaperPreview" type="button">Apply wallpaper</button></div></div></dialog></div><div class="settings-card"><div class="settings-card-heading"><h3>Glass effects</h3><p>Adjust the transparency and blur of panels.</p></div><div class="setting-row"><div><strong>Glass blur</strong><small>Lower values use fewer visual effects.</small></div><div class="settings-range"><input id="blurSelect" type="range" min="0" max="28" value="18"><output id="blurValue">18 px</output></div></div></div></section><section class="settings-page hidden" data-settings-page="performance">'+heading("Performance","Choose how much visual effect the desktop uses.")+'<div class="settings-card"><div class="setting-row"><div><strong>Lightweight mode</strong><small>Reduce blur and shadows throughout the desktop.</small></div><button class="switch-button" id="lightToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">This changes prototype visuals only. Real CPU and memory optimisation requires the native NEXUS services.</div></div></section><section class="settings-page hidden" data-settings-page="notifications">'+heading("Notifications","Control how alerts are presented.")+'<div class="settings-card"><div class="setting-row"><div><strong>Do Not Disturb</strong><small>Quiet notification alerts while enabled.</small></div><button class="switch-button" id="dndToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">Notification delivery is a prototype feature. System-wide notification control is planned.</div></div></section><section class="settings-page hidden" data-settings-page="accessibility">'+heading("Accessibility","Make the interface more comfortable to use.")+'<div class="settings-card"><div class="setting-row"><div><strong>Reduce motion</strong><small>Limit animated transitions and movement.</small></div><button class="switch-button" id="motionToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">The system also respects your browser’s reduced-motion preference.</div></div></section><section class="settings-page hidden" data-settings-page="system">'+heading("System","NEXUS OS prototype information and preferences.")+'<div class="settings-card system-info"><div><span>Product</span><strong>NEXUS OS</strong></div><div><span>Version</span><strong>Desktop Prototype 0.2</strong></div><div><span>Platform</span><strong>Browser preview</strong></div></div><div class="settings-card"><div class="settings-card-heading"><h3>Reset preferences</h3><p>Restore the appearance and quick-setting preferences to their defaults.</p></div><button class="action-button" id="resetPreferences">Reset all preferences</button><p class="settings-hint">Your Notes content will not be deleted.</p></div><div class="settings-card"><div class="settings-card-heading"><h3>Privacy and security</h3><p>Preferences are stored locally in this browser. This prototype does not have operating-system privileges or access to hardware controls.</p></div></div></section></div></div>';
if(app==="gaming")return heading("Gaming Hub","Discover your games and tune the experience.")+'<div class=card-grid><div class=content-card><h3>Steam</h3><p>Native Steam support is planned for the Linux-based future. This browser demo cannot launch Steam.</p></div><div class=content-card><h3>Performance</h3><p>Lightweight mode and reduced effects are available in Settings.</p></div><div class=content-card><h3>Controller</h3><p>Controller setup is a planned system feature.</p></div></div>';
if(app==="monitor")return heading("System Monitor","Prototype metrics, not real hardware telemetry.")+'<div class=card-grid><div class=content-card><h3>Memory</h3><p>Demo meter — no actual RAM data is being read.</p><div style="height:8px;background:#333;border-radius:10px;margin-top:12px"><div style="height:8px;width:42%;background:var(--accent);border-radius:10px"></div></div></div><div class=content-card><h3>Storage</h3><p>Demo meter — storage usage is not connected.</p></div><div class=content-card><h3>CPU</h3><p>Telemetry integration planned for native Linux backend.</p></div></div>';
if(app==="browser")return heading("Browser","Safe browser interface mockup.")+'<div class=browser-address><input id=browserUrl value="https://example.com" aria-label="URL"><button class=action-button id=browserGo>Open</button></div><div class=content-card style=margin-top:14px><h3>Browser preview</h3><p class=content-sub id=browserMsg>External pages are not loaded inside this demo. Use Open to visit a site in a new tab.</p></div>';
if(app==="terminal")return heading("Terminal","Command interface simulation. Commands do not execute on your computer.")+'<div class=terminal-box id=terminalOut>NEXUS Terminal Prototype v0.1\nSafe simulation — no system commands are executed.\nType help to see available demo commands.</div><div class=terminal-input><input id=terminalInput placeholder="Type a demo command…"><button class=action-button id=terminalSend>Run</button></div>';
if(app==="calculator")return heading("Calculator","Basic calculator.")+'<div class=calc><input id=calcDisplay class=calc-display readonly value="0" readonly><div class=calc-buttons>'+["7","8","9","÷","4","5","6","×","1","2","3","−","C","0",".","+","="].map(k=>'<button data-calc="'+k+'">'+k+'</button>').join("")+'</div></div>';
return heading(appNames[app],"Application preview");
}
function wireApp(app){
if(app==="notes"){const n=$("#notesText");n.value=localStorage.getItem("nexus-note")||"";n.oninput=()=>{localStorage.setItem("nexus-note",n.value);$("#notesStatus").textContent="Saved locally"};$("#clearNotes").onclick=()=>{n.value="";localStorage.removeItem("nexus-note");$("#notesStatus").textContent="Cleared"}}
if(app==="settings"){
 function applyWallpaper(id,persist=true){
  if(!setDesktopWallpaper(id,persist))return;
  $("[data-wallpaper]").forEach(item=>{const selected=item.dataset.wallpaper===id;item.classList.toggle("selected",selected);item.setAttribute("aria-pressed",String(selected));});
  $("#wallpaperStatus").textContent="Applied: "+$("#wallpaperGrid [data-wallpaper=\""+id+"\"] span").textContent;
 }
 const savedWallpaper=localStorage.getItem("nexus-wallpaper")||"alpine";
 applyWallpaper(savedWallpaper);
 let pendingWallpaper=null;
 const previewDialog=$("#wallpaperPreviewDialog");
 function closeWallpaperPreview(){if(previewDialog.open)previewDialog.close();pendingWallpaper=null;}
 function openWallpaperPreview(id){
  const item=$('[data-wallpaper="'+id+'"]');if(!item||!wallpaperCatalog[id])return;
  pendingWallpaper=id;
  $("#wallpaperPreviewTitle").textContent=item.querySelector("span").textContent;
  $("#wallpaperPreviewImage").src=wallpaperCatalog[id];
  $("#wallpaperPreviewImage").alt=item.querySelector("img").alt;
  $("#wallpaperPreviewCaption").textContent=id===localStorage.getItem("nexus-wallpaper")?"This is your currently applied wallpaper.":"Preview only — your desktop will not change until you apply it.";
  if(!previewDialog.open)previewDialog.showModal();
  $("#applyWallpaperPreview").focus();
 }
 $("[data-wallpaper]").forEach(item=>item.onclick=()=>openWallpaperPreview(item.dataset.wallpaper));
 $("[data-preview-close]").forEach(button=>button.onclick=closeWallpaperPreview);
 previewDialog.addEventListener("click",event=>{if(event.target===previewDialog)closeWallpaperPreview()});
 previewDialog.addEventListener("close",()=>{pendingWallpaper=null});
 $("#applyWallpaperPreview").onclick=()=>{
  const chosen=pendingWallpaper;
  if(chosen){applyWallpaper(chosen);$("#wallpaperStatus").textContent="Applied: "+$("#wallpaperGrid [data-wallpaper=\\""+chosen+"\\"] span").textContent;}
  closeWallpaperPreview();
 };
 $("[data-wallpaper-filter]").forEach(filter=>filter.onclick=()=>{
  const category=filter.dataset.wallpaperFilter;
  $("[data-wallpaper-filter]").forEach(item=>item.classList.toggle("active",item===filter));
  $("[data-wallpaper]").forEach(item=>item.hidden=category!=="all"&&item.dataset.category!==category);
 });
 const savedAccent=localStorage.getItem("nexus-accent")||"#ffad7a";
 const savedBlur=localStorage.getItem("nexus-blur")||"18";
 function setAccent(value){
  document.documentElement.style.setProperty("--accent",value);
  localStorage.setItem("nexus-accent",value);
  $("[data-accent]").forEach(swatch=>{
   const selected=swatch.dataset.accent===value;
   swatch.classList.toggle("selected",selected);
   swatch.setAttribute("aria-pressed",String(selected));
  });
  $("#accentStatus").textContent="Accent colour updated.";
 }
 $("[data-accent]").forEach(swatch=>swatch.onclick=()=>setAccent(swatch.dataset.accent));
 setAccent(savedAccent);
 const themeSaved=localStorage.getItem("nexus-theme")||"dark";
 function applyTheme(mode){
  const useLight=mode==="light"||(mode==="system"&&window.matchMedia&&window.matchMedia("(prefers-color-scheme: light)").matches);
  desktop.classList.toggle("theme-light",useLight);
  localStorage.setItem("nexus-theme",mode);
  $("[data-theme-choice]").forEach(button=>{const selected=button.dataset.themeChoice===mode;button.classList.toggle("selected",selected);button.setAttribute("aria-pressed",String(selected));});
  $("#themeStatus").textContent=(mode==="system"?"Following system appearance":mode.charAt(0).toUpperCase()+mode.slice(1)+" theme")+" selected.";
 }
 $("[data-theme-choice]").forEach(button=>button.onclick=()=>applyTheme(button.dataset.themeChoice));
 applyTheme(themeSaved);
 if(window.matchMedia){const scheme=window.matchMedia("(prefers-color-scheme: light)");scheme.addEventListener?.("change",()=>{if(localStorage.getItem("nexus-theme")==="system")applyTheme("system")});}
 const blur=$("#blurSelect"),blurValue=$("#blurValue");
 blur.value=savedBlur;
 function setBlur(){
  document.documentElement.style.setProperty("--blur",blur.value+"px");
  blurValue.value=blur.value+" px";
  blurValue.textContent=blur.value+" px";
  localStorage.setItem("nexus-blur",blur.value);
 }
 blur.oninput=setBlur;setBlur();
 function setSwitch(button,enabled,onChange){
  button.setAttribute("aria-checked",String(enabled));
  button.classList.toggle("enabled",enabled);
  button.textContent=enabled?"On":"Off";
  button.onclick=()=>{const next=button.getAttribute("aria-checked")!=="true";onChange(next);setSwitch(button,next,onChange)};
 }
 setSwitch($("#lightToggle"),controlState.power,enabled=>setControlPreference("power",enabled));
 setSwitch($("#dndToggle"),controlState.dnd,enabled=>setControlPreference("dnd",enabled));
 const motionSaved=localStorage.getItem("nexus-reduced-motion")==="true";
 function setMotion(enabled){
  document.body.classList.toggle("reduced-motion",enabled);
  localStorage.setItem("nexus-reduced-motion",String(enabled));
 }
 setMotion(motionSaved);
 setSwitch($("#motionToggle"),motionSaved,setMotion);
 $("[data-settings-section]").forEach(button=>button.onclick=()=>{
  const section=button.dataset.settingsSection;
  $("[data-settings-section]").forEach(item=>{
   const selected=item===button;
   item.classList.toggle("active",selected);
   if(selected)item.setAttribute("aria-current","page");else item.removeAttribute("aria-current");
  });
  $("[data-settings-page]").forEach(page=>{
   const selected=page.dataset.settingsPage===section;
   page.classList.toggle("hidden",!selected);
   if(selected){page.classList.remove("settings-enter");void page.offsetWidth;page.classList.add("settings-enter");}
  });
 });
 $("#resetPreferences").onclick=()=>{
  if(!window.confirm("Reset NEXUS appearance and quick-setting preferences? Your Notes will be kept."))return;
  ["nexus-accent","nexus-blur","nexus-theme","nexus-wallpaper","nexus-reduced-motion","nexus-brightness","nexus-volume",
   "nexus-control-wifi","nexus-control-bluetooth","nexus-control-dnd","nexus-control-power"].forEach(key=>localStorage.removeItem(key));
  document.documentElement.style.setProperty("--accent","#ffad7a");
  document.documentElement.style.setProperty("--blur","18px");
  desktop.classList.remove("theme-light");
  applyWallpaper("alpine",false);
  localStorage.setItem("nexus-theme","dark");
  document.body.classList.remove("reduced-motion");
  brightness.value="100";volume.value="65";updateBrightness();updateVolume();
  Object.entries(controlDefaults).forEach(([key,value])=>setControlPreference(key,value));
  setAccent("#ffad7a");blur.value="18";setBlur();
  setMotion(false);
  setSwitch($("#lightToggle"),false,enabled=>setControlPreference("power",enabled));
  setSwitch($("#dndToggle"),false,enabled=>setControlPreference("dnd",enabled));
  setSwitch($("#motionToggle"),false,setMotion);
  notify("NEXUS preferences restored");
 };
}
if(app==="browser")$("#browserGo").onclick=()=>{let url=$("#browserUrl").value.trim();if(!/^https?:\/\//i.test(url))url="https://"+url;try{const u=new URL(url);if(!["http:","https:"].includes(u.protocol))throw 0;window.open(u.href,"_blank","noopener");$("#browserMsg").textContent="Opened external site in a new tab."}catch{$("#browserMsg").textContent="Please enter a valid HTTP or HTTPS address."}};
if(app==="terminal"){const run=()=>{const inp=$("#terminalInput"),out=$("#terminalOut"),cmd=inp.value.trim().toLowerCase();const responses={help:"Demo commands: help, date, clear, about, apps, status",date:new Date().toString(),about:"NEXUS OS desktop prototype. No shell access.",apps:"Files, Browser, Notes, Terminal, Gaming Hub, System Monitor, Settings, Calculator",status:"Prototype status: UI active. System telemetry unavailable."};if(cmd==="clear")out.textContent="";else out.textContent+="\n> "+cmd+"\n"+(responses[cmd]||"Unknown demo command. Try help.");inp.value="";out.scrollTop=out.scrollHeight};$("#terminalSend").onclick=run;$("#terminalInput").onkeydown=e=>{if(e.key==="Enter")run()}}
if(app==="calculator"){
 let exp="";
 const display=$("#calcDisplay");
 function evaluateExpression(input){
  const source=input.replace(/\s/g,"");
  if(!source||source.length>120)throw Error("Invalid expression length");
  const tokens=source.match(/\d+(?:\.\d*)?|\.\d+|[()+\-*\/]/g)||[];
  if(tokens.length>64||tokens.join("")!==source)throw Error("Invalid expression");
  let pos=0;
  function primary(){
   const t=tokens[pos++];
   if(t==="("){
    const value=addSub();
    if(tokens[pos++]!==")")throw Error("Missing )");
    return value;
   }
   if(t==="+"||t==="-"){
    const value=primary();
    return t==="-"?-value:value;
   }
   if(!t||!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(t))throw Error("Expected number");
   const value=Number(t);
   if(!Number.isFinite(value))throw Error("Invalid number");
   return value;
  }
  function mulDiv(){
   let value=primary();
   while(tokens[pos]==="*"||tokens[pos]==="/"){
    const op=tokens[pos++],rhs=primary();
    if(op==="/"&&rhs===0)throw Error("Division by zero");
    value=op==="*"?value*rhs:value/rhs;
   }
   return value;
  }
  function addSub(){
   let value=mulDiv();
   while(tokens[pos]==="+"||tokens[pos]==="-"){
    const op=tokens[pos++],rhs=mulDiv();
    value=op==="+"?value+rhs:value-rhs;
   }
   return value;
  }
  const result=addSub();
  if(pos!==tokens.length||!Number.isFinite(result))throw Error("Invalid result");
  return result;
 }
 $$("[data-calc]").forEach(b=>b.onclick=()=>{
  const k=b.dataset.calc;
  if(k==="C"){exp="";display.value="0"}
  else if(k==="="){
   try{display.value=String(evaluateExpression(exp));exp=display.value}
   catch{display.value="Error";exp=""}
  }else if(exp.length<120){
   exp+=({"÷":"/","×":"*","−":"-"}[k]||k);
   display.value=exp;
  }else{
   display.value="Limit reached";
  }
 });
}
}
// Desktop window manager: stable drag, focus, snap, maximise and restore.
let zCounter=10;
let snapped=null;
let restoreRect=null;
let dragging=null;
function focusWindow(){win.style.zIndex=String(++zCounter)}
function clearWindowGeometry(){
 win.classList.remove("maximized","snapped-left","snapped-right");
 win.style.left="";win.style.top="";win.style.width="";win.style.height="";win.style.transform="";
}
function saveRestoreRect(){
 const r=win.getBoundingClientRect();
 restoreRect={left:r.left,top:r.top,width:r.width,height:r.height};
}
function restoreWindow(){
 clearWindowGeometry();
 if(restoreRect){
  win.style.left=restoreRect.left+"px";win.style.top=restoreRect.top+"px";
  win.style.width=restoreRect.width+"px";win.style.height=restoreRect.height+"px";
  win.style.transform="none";
 }
 maximized=false;snapped=null;
}
function maximizeWindow(){
 if(!maximized&&!snapped)saveRestoreRect();
 clearWindowGeometry();
 win.classList.add("maximized");
 maximized=true;snapped=null;
}
function snapWindow(side){
 if(!maximized&&!snapped)saveRestoreRect();
 clearWindowGeometry();
 win.classList.add(side==="left"?"snapped-left":"snapped-right");
 win.style.left=side==="left"?"8px":"calc(50vw + 4px)";
 win.style.top="60px";win.style.width="calc(50vw - 12px)";
 win.style.height="calc(100vh - 90px)";win.style.transform="none";
 snapped=side;maximized=false;
}
win.addEventListener("pointerdown",focusWindow);
const titlebar=win.querySelector(".window-titlebar");
titlebar.addEventListener("pointerdown",e=>{
 if(e.target.closest(".window-control")||e.button!==0)return;
 if(maximized||snapped){
  const old=restoreRect;
  clearWindowGeometry();maximized=false;snapped=null;
  if(old){
   const ratio=Math.min(1,Math.max(.15,(e.clientX-old.left)/old.width));
   win.style.width=old.width+"px";win.style.height=old.height+"px";
   win.style.left=(e.clientX-old.width*ratio)+"px";
   win.style.top=Math.max(56,e.clientY-18)+"px";
  }
 }
 const r=win.getBoundingClientRect();
 dragging={dx:e.clientX-r.left,dy:e.clientY-r.top,pointerId:e.pointerId};
 titlebar.setPointerCapture(e.pointerId);
});
titlebar.addEventListener("pointermove",e=>{
 if(!dragging||dragging.pointerId!==e.pointerId)return;
 const w=win.offsetWidth,h=win.offsetHeight;
 win.style.left=Math.max(0,Math.min(innerWidth-w,e.clientX-dragging.dx))+"px";
 win.style.top=Math.max(56,Math.min(innerHeight-h-65,e.clientY-dragging.dy))+"px";
 win.style.transform="none";
});
function finishDrag(e){
 if(!dragging)return;
 dragging=null;
 if(e.clientX<=14)snapWindow("left");
 else if(e.clientX>=innerWidth-14)snapWindow("right");
 else{win.classList.remove("snapped-left","snapped-right");snapped=null}
}
titlebar.addEventListener("pointerup",finishDrag);
titlebar.addEventListener("pointercancel",()=>{dragging=null});
titlebar.addEventListener("dblclick",e=>{
 if(e.target.closest(".window-control"))return;
 if(maximized||snapped)restoreWindow();else maximizeWindow();
});
$("#windowClose").onclick=()=>{win.classList.add("hidden");if(activeApp){$( ".dock-app[data-app='"+activeApp+"']" ).forEach(b=>b.classList.remove("running","minimized"))}activeApp=null};
$("#windowMin").onclick=()=>{win.classList.add("hidden");if(activeApp){$( ".dock-app[data-app='"+activeApp+"']" ).forEach(b=>b.classList.add("minimized"))}notify("Window minimised")};
$("#windowMax").onclick=()=>{if(maximized||snapped)restoreWindow();else maximizeWindow()};
$("#appSearch").oninput=e=>{const term=e.target.value.toLowerCase();$$(".app-item").forEach(item=>item.style.display=item.textContent.toLowerCase().includes(term)?"flex":"none")};
$$(".app-item").forEach(item=>item.onclick=()=>openApp(item.dataset.app));
setDesktopWallpaper(localStorage.getItem("nexus-wallpaper")||"alpine",false);
const savedAccent=localStorage.getItem("nexus-accent");document.documentElement.style.setProperty("--accent",savedAccent||"#ffad7a");const savedBlur=localStorage.getItem("nexus-blur");document.documentElement.style.setProperty("--blur",(savedBlur||"18")+"px");if(localStorage.getItem("nexus-reduced-motion")==="true")document.body.classList.add("reduced-motion");
})();