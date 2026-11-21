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
let startupCustomWallpaperUrl=null;
async function restoreCustomWallpaperAtStartup(){
 if(localStorage.getItem("nexus-wallpaper")!=="custom"||!("indexedDB" in window))return;
 try{
  const db=await new Promise((resolve,reject)=>{
   const request=indexedDB.open("nexus-wallpaper-store",1);
   request.onupgradeneeded=()=>{if(!request.result.objectStoreNames.contains("wallpapers"))request.result.createObjectStore("wallpapers");};
   request.onsuccess=()=>resolve(request.result);
   request.onerror=()=>reject(new Error("Could not open local wallpaper storage."));
  });
  const blob=await new Promise((resolve,reject)=>{
   const tx=db.transaction("wallpapers","readonly");
   const request=tx.objectStore("wallpapers").get("custom");
   request.onsuccess=()=>resolve(request.result||null);
   request.onerror=()=>reject(new Error("Could not read the saved wallpaper."));
   tx.oncomplete=()=>db.close();
  });
  if(blob&&["image/jpeg","image/png","image/webp"].includes(blob.type)){
   startupCustomWallpaperUrl=URL.createObjectURL(blob);
   desktop.style.backgroundImage='linear-gradient(120deg,rgba(8,13,25,.72),rgba(11,13,30,.24)),url("'+startupCustomWallpaperUrl+'")';
  }else if(!blob){
   localStorage.setItem("nexus-wallpaper","alpine");
   setDesktopWallpaper("alpine",false);
  }
 }catch(error){console.warn("NEXUS custom wallpaper restore:",error);}
}
let activeApp=null, toastTimer, maximized=false;
const appNames={files:"Files",browser:"Browser",notes:"Notes",terminal:"Terminal",gaming:"Gaming Hub",monitor:"System Monitor",settings:"Settings",calculator:"Calculator"};
window.NexusAppRegistry.list().forEach(app=>{appNames[app.id]=app.name});
function clock(){const d=new Date();$("#clock").textContent=d.toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"})}
clock();setInterval(clock,30000);
function notify(msg){toast.textContent=msg;toast.classList.remove("hidden");clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.add("hidden"),2200)}
function closePanels(){control.classList.add("hidden");launcher.classList.add("hidden")}
$("#controlButton").onclick=()=>{launcher.classList.add("hidden");control.classList.toggle("hidden")};
$("#notificationButton").onclick=()=>{launcher.classList.add("hidden");control.classList.remove("hidden");$("#controlNotifications").scrollIntoView({block:"nearest",behavior:document.body.classList.contains("reduced-motion")?"auto":"smooth"})};
$("#clearNotifications").onclick=()=>{$("#notificationList").innerHTML='<div class="notification-empty"><p>You are all caught up.</p><small>Notifications will appear here.</small></div>';notify("Notifications cleared")};
$("#launcherButton").onclick=()=>{control.classList.add("hidden");launcher.classList.toggle("hidden");$("#appSearch").focus()};
$$("[data-close]").forEach(b=>b.onclick=()=>$("#"+b.dataset.close).classList.add("hidden"));
document.addEventListener("keydown",e=>{if(e.key==="Escape"){const launcherWasOpen=!launcher.classList.contains("hidden"),controlWasOpen=!control.classList.contains("hidden");control.classList.add("hidden");launcher.classList.add("hidden");if(launcherWasOpen)$("#launcherButton").focus();else if(controlWasOpen)$("#controlButton").focus()}});
const controlDefaults={dnd:false,power:false};
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
$$("[data-toggle]").forEach(button=>{
 const key=button.dataset.toggle;
 const saved=localStorage.getItem("nexus-control-"+key);
 applyControlToggle(button,saved===null?controlDefaults[key]:saved==="true");
 button.onclick=()=>applyControlToggle(button,!controlState[key]);
});
const brightness=$("#brightness");
const savedBrightness=localStorage.getItem("nexus-brightness");
if(savedBrightness!==null)brightness.value=savedBrightness;
function updateSlider(input,output,key){
 output.value=input.value+"%";
 output.textContent=input.value+"%";
 localStorage.setItem(key,input.value);
}
function updateBrightness(){
 updateSlider(brightness,$("#brightnessValue"),"nexus-brightness");
 desktop.style.filter="brightness("+Number(brightness.value)/100+")";
}
brightness.oninput=updateBrightness;
updateBrightness();
$("#volumeValue").textContent="Unavailable";
$$("[data-app]").forEach(b=>b.addEventListener("click",()=>{
 const app=b.dataset.app;
 if(b.classList.contains("dock-app")&&activeApp===app){
  if(win.classList.contains("hidden")){win.classList.remove("hidden");$( ".dock-app[data-app='"+app+"']")?.classList.remove("minimized");focusWindow()}
  else focusWindow();
  closePanels();
  return;
 }
 openApp(app);
}));
function openApp(app){if(!appNames[app])return;if(activeApp){window.NexusAppRegistry.unmountApp(activeApp);$$( ".dock-app[data-app='"+activeApp+"']" ).forEach(b=>b.classList.remove("running","minimized"))}activeApp=app;clearWindowGeometry();restoreRect=null;snapped=null;closePanels();launcher.classList.add("hidden");win.classList.remove("hidden");maximized=false;$("#windowMax").setAttribute("aria-label","Maximize");title.textContent=appNames[app];content.innerHTML=appView(app);if(app==="settings")window.NexusAppRegistry.enhanceSettings(content);wireApp(app);$$( ".dock-app[data-app]" ).forEach(b=>{b.classList.toggle("running",b.dataset.app===app);b.classList.remove("minimized")});focusWindow()}
function appView(app){
const heading=(t,s)=>'<h2 class="content-title">'+t+'</h2><p class="content-sub">'+s+'</p>';
const registered=window.NexusAppRegistry.get(app);
if(registered)return registered.render();
if(app==="notes")return heading("Notes","Your notes are saved locally in this browser.")+'<textarea class="note-area" id="notesText" placeholder="Write something…"></textarea><div style="display:flex;justify-content:space-between;margin-top:10px"><small class=content-sub id=notesStatus>Autosave ready</small><button class=action-button id=clearNotes>Clear note</button></div>';
if(app==="settings")return '<div class="settings-layout"><aside class="settings-sidebar" aria-label="Settings categories"><p class="settings-kicker">PREFERENCES</p><button class="settings-nav active" data-settings-section="appearance"><span>◐</span> Appearance</button><button class="settings-nav" data-settings-section="performance"><span>ϟ</span> Performance</button><button class="settings-nav" data-settings-section="notifications"><span>◉</span> Notifications</button><button class="settings-nav" data-settings-section="accessibility"><span>◎</span> Accessibility</button><button class="settings-nav" data-settings-section="system"><span>⌘</span> System</button></aside><div class="settings-main"><section class="settings-page" data-settings-page="appearance">'+heading("Appearance","Make NEXUS feel like your own.")+'<div class="settings-card"><div class="settings-card-heading"><h3>Desktop theme</h3><p>Choose the overall look of your workspace.</p></div><div class="theme-options"><button class="theme-choice" data-theme-choice="dark" type="button">Dark</button><button class="theme-choice" data-theme-choice="light" type="button">Light</button><button class="theme-choice" data-theme-choice="system" type="button">System</button></div><p class="settings-hint" id="themeStatus">Dark theme selected.</p></div><div class="settings-card"><div class="settings-card-heading"><h3>Accent colour</h3><p>Choose the highlight used across the interface.</p></div><div class="accent-options"><button class="accent-swatch" data-accent="#ffad7a" aria-label="Copper accent" title="Copper"></button><button class="accent-swatch" data-accent="#8b7cff" aria-label="Violet accent" title="Violet"></button><button class="accent-swatch" data-accent="#44c9e8" aria-label="Cyan accent" title="Cyan"></button><button class="accent-swatch" data-accent="#5ed3a3" aria-label="Emerald accent" title="Emerald"></button><button class="accent-swatch" data-accent="#ee82b6" aria-label="Rose accent" title="Rose"></button></div><p class="settings-hint" id="accentStatus">Copper is the default NEXUS accent.</p><div class="wallpaper-accent-suggestions"><div class="wallpaper-accent-heading"><strong>Wallpaper colour suggestions</strong><span>Automatically sampled from your wallpaper</span></div><div class="suggested-accent-options" id="suggestedAccentOptions" aria-label="Suggested accent colours"><span class="suggested-accent-empty">Choose a wallpaper to generate matching colours.</span></div><p class="settings-hint" id="suggestedAccentStatus" role="status">Suggestions will appear when you preview a wallpaper.</p></div></div><div class="settings-card wallpaper-card"><div class="settings-card-heading"><h3>Desktop wallpaper</h3><p>Choose a photographic background for your workspace. Images are served by Unsplash.</p></div><div class="wallpaper-filters" role="group" aria-label="Wallpaper categories"><button class="wallpaper-filter active" data-wallpaper-filter="all" type="button">All</button><button class="wallpaper-filter" data-wallpaper-filter="nature" type="button">Nature</button><button class="wallpaper-filter" data-wallpaper-filter="space" type="button">Space</button><button class="wallpaper-filter" data-wallpaper-filter="architecture" type="button">Architecture</button></div><div class="wallpaper-grid" id="wallpaperGrid"><button class="wallpaper-option" type="button" data-wallpaper="mountain-night" data-category="nature" aria-label="Apply mountain night wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1725663656850-7bc515816fcd?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Starry sky above a mountain range"><span>Mountain Night</span></button><button class="wallpaper-option" type="button" data-wallpaper="alpine" data-category="nature" aria-label="Apply alpine landscape wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Dramatic alpine mountain peaks"><span>Alpine</span></button><button class="wallpaper-option" type="button" data-wallpaper="forest" data-category="nature" aria-label="Apply forest wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Sunlight through a green forest"><span>Forest</span></button><button class="wallpaper-option" type="button" data-wallpaper="cosmos" data-category="space" aria-label="Apply cosmos wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Colourful deep space nebula"><span>Cosmos</span></button><button class="wallpaper-option" type="button" data-wallpaper="city" data-category="architecture" aria-label="Apply city wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="City skyline at dusk"><span>City Lights</span></button><button class="wallpaper-option" type="button" data-wallpaper="modern" data-category="architecture" aria-label="Apply architecture wallpaper"><img loading="lazy" src="https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&amp;fit=crop&amp;w=520&amp;q=75" alt="Modern architectural structure"><span>Architecture</span></button><div class="custom-wallpaper-import">\
 <div class="custom-wallpaper-copy"><strong>Use your own image</strong><small>Choose a JPEG, PNG or WebP image up to 8 MB. Your image stays on this device.</small></div>\
 <input id="customWallpaperFile" class="custom-wallpaper-input" type="file" accept="image/jpeg,image/png,image/webp" aria-label="Choose a custom wallpaper image">\
 <button class="action-button custom-wallpaper-button" id="chooseCustomWallpaper" type="button">Import image</button>\
 <button class="action-button custom-wallpaper-remove" id="removeCustomWallpaper" type="button" hidden>Remove custom image</button>\
 <p class="settings-hint custom-wallpaper-status" id="customWallpaperStatus" role="status">No custom wallpaper imported.</p>\
</div></div><div class="wallpaper-footer"><p class="settings-hint" id="wallpaperStatus">Choose a wallpaper to see a larger preview before applying it.</p><a href="https://unsplash.com/license" target="_blank" rel="noopener noreferrer">Unsplash licence</a></div><dialog class="wallpaper-preview-dialog" id="wallpaperPreviewDialog" aria-labelledby="wallpaperPreviewTitle"><div class="wallpaper-preview-shell"><div class="wallpaper-preview-heading"><div><p class="settings-kicker">DESKTOP PREVIEW</p><h3 id="wallpaperPreviewTitle">Wallpaper preview</h3></div><button class="preview-close" type="button" data-preview-close aria-label="Close preview">×</button></div><img id="wallpaperPreviewImage" class="wallpaper-preview-image" alt="Large preview of the selected wallpaper"><p class="wallpaper-preview-caption" id="wallpaperPreviewCaption">This will become your desktop background.</p><div class="wallpaper-preview-actions"><button class="action-button preview-cancel" type="button" data-preview-close>Cancel</button><button class="action-button preview-apply" id="applyWallpaperPreview" type="button">Apply wallpaper</button></div></div></dialog></div><div class="settings-card"><div class="settings-card-heading"><h3>Glass effects</h3><p>Adjust the transparency and blur of panels.</p></div><div class="setting-row"><div><strong>Glass blur</strong><small>Lower values use fewer visual effects.</small></div><div class="settings-range"><input id="blurSelect" type="range" min="0" max="28" value="18"><output id="blurValue">18 px</output></div></div></div></section><section class="settings-page hidden" data-settings-page="performance">'+heading("Performance","Choose how much visual effect the desktop uses.")+'<div class="settings-card"><div class="setting-row"><div><strong>Lightweight mode</strong><small>Reduce blur and shadows throughout the desktop.</small></div><button class="switch-button" id="lightToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">This changes prototype visuals only. Real CPU and memory optimisation requires the native NEXUS services.</div></div></section><section class="settings-page hidden" data-settings-page="notifications">'+heading("Notifications","Control how alerts are presented.")+'<div class="settings-card"><div class="setting-row"><div><strong>Do Not Disturb</strong><small>Quiet notification alerts while enabled.</small></div><button class="switch-button" id="dndToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">Notification delivery is a prototype feature. System-wide notification control is planned.</div></div></section><section class="settings-page hidden" data-settings-page="accessibility">'+heading("Accessibility","Make the interface more comfortable to use.")+'<div class="settings-card"><div class="setting-row"><div><strong>Reduce motion</strong><small>Limit animated transitions and movement.</small></div><button class="switch-button" id="motionToggle" type="button" role="switch" aria-checked="false">Off</button></div><div class="settings-row-note">The system also respects your browser’s reduced-motion preference.</div></div></section><section class="settings-page hidden" data-settings-page="system">'+heading("System","NEXUS OS prototype information and preferences.")+'<div class="settings-card system-info"><div><span>Product</span><strong>NEXUS OS</strong></div><div><span>Version</span><strong>Desktop Prototype 0.2</strong></div><div><span>Platform</span><strong>Browser preview</strong></div></div><div class="settings-card"><div class="settings-card-heading"><h3>Reset preferences</h3><p>Restore the appearance and quick-setting preferences to their defaults.</p></div><button class="action-button" id="resetPreferences">Reset all preferences</button><p class="settings-hint">Your Notes content will not be deleted.</p></div><div class="settings-card"><div class="settings-card-heading"><h3>Privacy and security</h3><p>Preferences are stored locally in this browser. This prototype does not have operating-system privileges or access to hardware controls.</p></div></div></section></div></div>';
if(app==="gaming")return heading("Gaming Hub","Discover your games and tune the experience.")+'<div class=card-grid><div class=content-card><h3>Steam</h3><p>Native Steam support is planned for the Linux-based future. This browser demo cannot launch Steam.</p></div><div class=content-card><h3>Performance</h3><p>Lightweight mode and reduced effects are available in Settings.</p></div><div class=content-card><h3>Controller</h3><p>Controller setup is a planned system feature.</p></div></div>';
if(app==="browser")return heading("Browser","Safe browser interface mockup.")+'<div class=browser-address><input id=browserUrl value="https://example.com" aria-label="URL"><button class=action-button id=browserGo>Open</button></div><div class=content-card style=margin-top:14px><h3>Browser preview</h3><p class=content-sub id=browserMsg>External pages are not loaded inside this demo. Use Open to visit a site in a new tab.</p></div>';
if(app==="terminal")return heading("Terminal","Command interface simulation. Commands do not execute on your computer.")+'<div class=terminal-box id=terminalOut>NEXUS Terminal Prototype v0.1\nSafe simulation — no system commands are executed.\nType help to see available demo commands.</div><div class=terminal-input><input id=terminalInput placeholder="Type a demo command…"><button class=action-button id=terminalSend>Run</button></div>';
if(app==="calculator")return heading("Calculator","Basic calculator.")+'<div class=calc><input id=calcDisplay class=calc-display readonly value="0" readonly><div class=calc-buttons>'+["7","8","9","÷","4","5","6","×","1","2","3","−","C","0",".","+","="].map(k=>'<button data-calc="'+k+'">'+k+'</button>').join("")+'</div></div>';
return heading(appNames[app],"Application preview");
}
function wireApp(app){
if(window.NexusAppRegistry.mountApp(app,content,{notify}))return;
if(app==="notes"){const n=$("#notesText");n.value=localStorage.getItem("nexus-note")||"";n.oninput=()=>{localStorage.setItem("nexus-note",n.value);$("#notesStatus").textContent="Saved locally"};$("#clearNotes").onclick=()=>{n.value="";localStorage.removeItem("nexus-note");$("#notesStatus").textContent="Cleared"}}
if(app==="settings"){
 function applyWallpaper(id,persist=true){
  if(!setDesktopWallpaper(id,persist))return;
  $$("[data-wallpaper]").forEach(item=>{const selected=item.dataset.wallpaper===id;item.classList.toggle("selected",selected);item.setAttribute("aria-pressed",String(selected));});
  $("#wallpaperStatus").textContent="Applied: "+$("#wallpaperGrid [data-wallpaper=\""+id+"\"] span").textContent;
 }
 const customWallpaperKey="custom";
 let customWallpaperBlob=null;
 let customWallpaperUrl=null;
 let pendingCustomWallpaper=null;
 let pendingCustomUrl=null;
 function openWallpaperDatabase(){
  return new Promise((resolve,reject)=>{
   if(!("indexedDB" in window)){reject(new Error("Local image storage is not supported in this browser."));return;}
   const request=indexedDB.open("nexus-wallpaper-store",1);
   request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains("wallpapers"))db.createObjectStore("wallpapers");};
   request.onsuccess=()=>resolve(request.result);
   request.onerror=()=>reject(new Error("Could not open local wallpaper storage."));
  });
 }
 async function readCustomWallpaper(){
  const db=await openWallpaperDatabase();
  return new Promise((resolve,reject)=>{
   const tx=db.transaction("wallpapers","readonly");
   const request=tx.objectStore("wallpapers").get(customWallpaperKey);
   request.onsuccess=()=>{resolve(request.result||null);db.close();};
   request.onerror=()=>{db.close();reject(new Error("Could not read the saved custom wallpaper."));};
  });
 }
 async function saveCustomWallpaper(blob){
  const db=await openWallpaperDatabase();
  return new Promise((resolve,reject)=>{
   const tx=db.transaction("wallpapers","readwrite");
   tx.objectStore("wallpapers").put(blob,customWallpaperKey);
   tx.oncomplete=()=>{db.close();resolve();};
   tx.onerror=()=>{db.close();reject(new Error("Could not save the custom wallpaper."));};
   tx.onabort=()=>{db.close();reject(new Error("Saving the custom wallpaper was cancelled."));};
  });
 }
 async function deleteCustomWallpaper(){
  const db=await openWallpaperDatabase();
  return new Promise((resolve,reject)=>{
   const tx=db.transaction("wallpapers","readwrite");
   tx.objectStore("wallpapers").delete(customWallpaperKey);
   tx.oncomplete=()=>{db.close();resolve();};
   tx.onerror=()=>{db.close();reject(new Error("Could not remove the saved custom wallpaper."));};
   tx.onabort=()=>{db.close();reject(new Error("Removing the custom wallpaper was cancelled."));};
  });
 }
 function releaseCustomWallpaperUrls(){
  if(customWallpaperUrl){URL.revokeObjectURL(customWallpaperUrl);customWallpaperUrl=null;}
  if(pendingCustomUrl){URL.revokeObjectURL(pendingCustomUrl);pendingCustomUrl=null;}
 }
 function setCustomWallpaper(blob,url){
  if(customWallpaperUrl&&customWallpaperUrl!==url)URL.revokeObjectURL(customWallpaperUrl);
  customWallpaperBlob=blob;customWallpaperUrl=url;
  desktop.style.backgroundImage='linear-gradient(120deg,rgba(8,13,25,.72),rgba(11,13,30,.24)),url("'+url+'")';
  localStorage.setItem("nexus-wallpaper","custom");
  $$("[data-wallpaper]").forEach(item=>{item.classList.remove("selected");item.setAttribute("aria-pressed","false");});
  $("#wallpaperStatus").textContent="Applied: Custom wallpaper";
  $("#customWallpaperStatus").textContent="Your custom wallpaper is saved on this device.";
  $("#removeCustomWallpaper").hidden=false;
 }
 async function restoreCustomWallpaper(){
  try{
   if(startupCustomWallpaperUrl){customWallpaperUrl=startupCustomWallpaperUrl;startupCustomWallpaperUrl=null;}
   const blob=await readCustomWallpaper();
   if(!blob)return;
   if(!["image/jpeg","image/png","image/webp"].includes(blob.type))return;
   const url=customWallpaperUrl||URL.createObjectURL(blob);
   customWallpaperBlob=blob;customWallpaperUrl=url;
   if(localStorage.getItem("nexus-wallpaper")==="custom"){
    desktop.style.backgroundImage='linear-gradient(120deg,rgba(8,13,25,.72),rgba(11,13,30,.24)),url("'+url+'")';
    $("#wallpaperStatus").textContent="Applied: Custom wallpaper";
   }
   $("#customWallpaperStatus").textContent="A custom wallpaper is saved on this device.";
   $("#removeCustomWallpaper").hidden=false;
  }catch(error){$("#customWallpaperStatus").textContent=error.message;}
 }
 const customInput=$("#customWallpaperFile");
 $("#chooseCustomWallpaper").onclick=()=>customInput.click();
 customInput.onchange=async()=>{
  const file=customInput.files&&customInput.files[0];customInput.value="";
  if(!file)return;
  if(!["image/jpeg","image/png","image/webp"].includes(file.type)){
   $("#customWallpaperStatus").textContent="Unsupported image. Please choose JPEG, PNG or WebP.";return;
  }
  if(file.size>8*1024*1024){
   $("#customWallpaperStatus").textContent="That image is larger than 8 MB. Choose a smaller file.";return;
  }
  const candidateUrl=URL.createObjectURL(file);
  const image=new Image();
  image.onload=()=>{
   if(!image.naturalWidth||!image.naturalHeight||image.naturalWidth>12000||image.naturalHeight>12000){
    URL.revokeObjectURL(candidateUrl);
    $("#customWallpaperStatus").textContent="This image has invalid or unusually large dimensions.";return;
   }
   if(pendingCustomUrl)URL.revokeObjectURL(pendingCustomUrl);
   pendingCustomUrl=candidateUrl;pendingCustomWallpaper=file;pendingAccent=null;
   $("#wallpaperPreviewTitle").textContent=file.name;
   $("#wallpaperPreviewImage").src=candidateUrl;
   suggestWallpaperAccents(candidateUrl);
   $("#wallpaperPreviewImage").alt="Preview of your imported image";
   $("#wallpaperPreviewCaption").textContent="Preview only — your current wallpaper will remain until you apply this image.";
   $("#applyWallpaperPreview").textContent="Save and apply";
   $("#customWallpaperStatus").textContent="Image ready to preview: "+file.name;
   if(!previewDialog.open)previewDialog.showModal();
   $("#applyWallpaperPreview").focus();
  };
  image.onerror=()=>{URL.revokeObjectURL(candidateUrl);$("#customWallpaperStatus").textContent="The selected file could not be read as a valid image.";};
  image.src=candidateUrl;
 };
 $("#removeCustomWallpaper").onclick=async()=>{
  try{
   await deleteCustomWallpaper();
   const wasApplied=localStorage.getItem("nexus-wallpaper")==="custom";
   if(wasApplied){localStorage.removeItem("nexus-wallpaper");setDesktopWallpaper("alpine",false);localStorage.setItem("nexus-wallpaper","alpine");}
   if(customWallpaperUrl){URL.revokeObjectURL(customWallpaperUrl);customWallpaperUrl=null;}
   customWallpaperBlob=null;
   $("#removeCustomWallpaper").hidden=true;
   $("#customWallpaperStatus").textContent="Custom wallpaper removed from this device.";
   $("#wallpaperStatus").textContent=wasApplied?"Applied: Alpine":"Your current wallpaper is unchanged.";
  }catch(error){$("#customWallpaperStatus").textContent=error.message;}
 };
 restoreCustomWallpaper();
 const savedWallpaper=localStorage.getItem("nexus-wallpaper")||"alpine";
 applyWallpaper(savedWallpaper);
 let pendingWallpaper=null;
 const previewDialog=$("#wallpaperPreviewDialog");
 function closeWallpaperPreview(){if(previewDialog.open)previewDialog.close();pendingWallpaper=null;pendingCustomWallpaper=null;pendingAccent=null;accentSuggestionToken++;if(pendingCustomUrl){URL.revokeObjectURL(pendingCustomUrl);pendingCustomUrl=null;}}
 let pendingAccent=null;
 let accentSuggestionToken=0;
 function rgbToHsl(r,g,b){
  r/=255;g/=255;b/=255;
  const max=Math.max(r,g,b),min=Math.min(r,g,b),delta=max-min;
  let h=0,sat=0,l=(max+min)/2;
  if(delta){sat=delta/(1-Math.abs(2*l-1));switch(max){case r:h=((g-b)/delta)%6;break;case g:h=(b-r)/delta+2;break;default:h=(r-g)/delta+4;}h*=60;if(h<0)h+=360;}
  return {h,s:sat,l};
 }
 function hslToHex(h,sat,l){
  const chroma=(1-Math.abs(2*l-1))*sat,x=chroma*(1-Math.abs((h/60)%2-1)),m=l-chroma/2;
  let rgb=h<60?[chroma,x,0]:h<120?[x,chroma,0]:h<180?[0,chroma,x]:h<240?[0,x,chroma]:h<300?[x,0,chroma]:[chroma,0,x];
  return "#"+rgb.map(value=>Math.round((value+m)*255).toString(16).padStart(2,"0")).join("");
 }
 function sampleWallpaperHue(image){
  const canvas=document.createElement("canvas");canvas.width=48;canvas.height=48;
  const context=canvas.getContext("2d",{willReadFrequently:true});
  if(!context)throw new Error("Colour sampling is unavailable.");
  context.drawImage(image,0,0,48,48);
  const pixels=context.getImageData(0,0,48,48).data;
  const bins=new Array(24).fill(0);
  for(let i=0;i<pixels.length;i+=16){
   if(pixels[i+3]<180)continue;
   const {h,s,l}=rgbToHsl(pixels[i],pixels[i+1],pixels[i+2]);
   if(s<.2||l<.12||l>.88)continue;
   bins[Math.floor(h/15)%24]+=s*(.5+Math.min(l,1-l));
  }
  const strongest=bins.indexOf(Math.max(...bins));
  if(strongest<0||bins[strongest]===0)throw new Error("No clear accent colour was found.");
  return strongest*15+7.5;
 }
 function renderWallpaperAccentSuggestions(hue){
  const options=[{shift:0,label:"Main match"},{shift:28,label:"Warm harmony"},{shift:-28,label:"Cool harmony"}];
  const container=$("#suggestedAccentOptions");container.innerHTML="";
  options.forEach(option=>{
   const color=hslToHex((hue+option.shift+360)%360,.68,.62);
   const button=document.createElement("button");
   button.type="button";button.className="suggested-accent-swatch";
   button.dataset.suggestedAccent=color;button.style.setProperty("--suggested-color",color);
   button.title=option.label+" "+color;button.setAttribute("aria-label",option.label+" accent "+color);
   button.setAttribute("aria-pressed",String(pendingAccent===color));
   if(pendingAccent===color)button.classList.add("selected");
   button.addEventListener("click",()=>{
    pendingAccent=color;
    container.querySelectorAll("[data-suggested-accent]").forEach(option=>{
     const selected=option.dataset.suggestedAccent===color;
     option.classList.toggle("selected",selected);
     option.setAttribute("aria-pressed",String(selected));
    });
    $("#suggestedAccentStatus").textContent="Accent selected for this preview. Apply wallpaper to save it, or Cancel to discard it.";
   });
   const label=document.createElement("span");label.textContent=option.label;
   button.append(label);container.append(button);
  });
  $("#suggestedAccentStatus").textContent="Choose a colour to preview it. It will only be saved if you apply the wallpaper.";
 }
 function suggestWallpaperAccents(source){
  const token=++accentSuggestionToken;
  $("#suggestedAccentOptions").innerHTML='<span class="suggested-accent-empty">Analysing wallpaper colours…</span>';
  $("#suggestedAccentStatus").textContent="Sampling the image locally in your browser.";
  const image=new Image();
  if(!source.startsWith("blob:")&&!source.startsWith("data:"))image.crossOrigin="anonymous";
  image.onload=()=>{
   if(token!==accentSuggestionToken)return;
   try{renderWallpaperAccentSuggestions(sampleWallpaperHue(image));}
   catch(error){console.warn("NEXUS wallpaper colour sampling failed:",error);const blocked=error&&error.name==="SecurityError";$("#suggestedAccentOptions").innerHTML='<span class="suggested-accent-empty">Could not sample this image. Try a custom image or another wallpaper.</span>';$("#suggestedAccentStatus").textContent=blocked?"Browser security blocked pixel access (SecurityError/CORS). Try importing the image locally.":"Colour sampling failed; your wallpaper and current accent are unaffected.";}
  };
  image.onerror=()=>{
   if(token!==accentSuggestionToken)return;
   $("#suggestedAccentOptions").innerHTML='<span class="suggested-accent-empty">Colour suggestions are unavailable for this image.</span>';
   $("#suggestedAccentStatus").textContent="Your wallpaper preview still works normally.";
  };
  image.src=source;
 }
 function openWallpaperPreview(id){
  const item=$('[data-wallpaper="'+id+'"]');if(!item||!wallpaperCatalog[id])return;
  pendingWallpaper=id;pendingCustomWallpaper=null;pendingAccent=null;
  $("#applyWallpaperPreview").textContent="Apply wallpaper";
  $("#wallpaperPreviewTitle").textContent=item.querySelector("span").textContent;
  $("#wallpaperPreviewImage").src=wallpaperCatalog[id];
  suggestWallpaperAccents(wallpaperCatalog[id]);
  $("#wallpaperPreviewImage").alt=item.querySelector("img").alt;
  $("#wallpaperPreviewCaption").textContent=id===localStorage.getItem("nexus-wallpaper")?"This is your currently applied wallpaper.":"Preview only — your desktop will not change until you apply it.";
  if(!previewDialog.open)previewDialog.showModal();
  $("#applyWallpaperPreview").focus();
 }
 $$("[data-wallpaper]").forEach(item=>item.onclick=()=>openWallpaperPreview(item.dataset.wallpaper));
 $$("[data-preview-close]").forEach(button=>button.onclick=closeWallpaperPreview);
 previewDialog.addEventListener("click",event=>{if(event.target===previewDialog)closeWallpaperPreview()});
 previewDialog.addEventListener("close",()=>{pendingWallpaper=null;pendingCustomWallpaper=null;pendingAccent=null;if(pendingCustomUrl){URL.revokeObjectURL(pendingCustomUrl);pendingCustomUrl=null;}$("#applyWallpaperPreview").textContent="Apply wallpaper";});
 $("#applyWallpaperPreview").onclick=async()=>{
  const chosen=pendingWallpaper;
  const customFile=pendingCustomWallpaper;
  const customUrl=pendingCustomUrl;
  if(customFile&&customUrl){
   try{
    await saveCustomWallpaper(customFile);
    pendingCustomUrl=null;
    setCustomWallpaper(customFile,customUrl);
    $("#applyWallpaperPreview").textContent="Apply wallpaper";
   }catch(error){$("#customWallpaperStatus").textContent=error.message;return;}
  }else if(chosen){
   applyWallpaper(chosen);
   const chosenItem=$('[data-wallpaper="'+chosen+'"]');
   $("#wallpaperStatus").textContent="Applied: "+chosenItem.querySelector("span").textContent;
   $("#applyWallpaperPreview").textContent="Apply wallpaper";
  }
  if(pendingAccent)setAccent(pendingAccent);
  closeWallpaperPreview();
 };
 $$("[data-wallpaper-filter]").forEach(filter=>filter.onclick=()=>{
  const category=filter.dataset.wallpaperFilter;
  $$("[data-wallpaper-filter]").forEach(item=>item.classList.toggle("active",item===filter));
  $$("[data-wallpaper]").forEach(item=>item.hidden=category!=="all"&&item.dataset.category!==category);
 });
 const savedAccent=localStorage.getItem("nexus-accent")||"#ffad7a";
 const savedBlur=localStorage.getItem("nexus-blur")||"18";
 function setAccent(value){
  document.documentElement.style.setProperty("--accent",value);
  localStorage.setItem("nexus-accent",value);
  $$("[data-accent]").forEach(swatch=>{
   const selected=swatch.dataset.accent===value;
   swatch.classList.toggle("selected",selected);
   swatch.setAttribute("aria-pressed",String(selected));
  });
  $$("[data-suggested-accent]").forEach(button=>{const selected=button.dataset.suggestedAccent===value;button.classList.toggle("selected",selected);button.setAttribute("aria-pressed",String(selected));});
  $("#accentStatus").textContent="Accent colour updated.";
 }
 $$("[data-accent]").forEach(swatch=>swatch.onclick=()=>setAccent(swatch.dataset.accent));
 setAccent(savedAccent);
 const themeSaved=localStorage.getItem("nexus-theme")||"dark";
 function applyTheme(mode){
  const useLight=mode==="light"||(mode==="system"&&window.matchMedia&&window.matchMedia("(prefers-color-scheme: light)").matches);
  desktop.classList.toggle("theme-light",useLight);
  localStorage.setItem("nexus-theme",mode);
  $$("[data-theme-choice]").forEach(button=>{const selected=button.dataset.themeChoice===mode;button.classList.toggle("selected",selected);button.setAttribute("aria-pressed",String(selected));});
  $("#themeStatus").textContent=(mode==="system"?"Following system appearance":mode.charAt(0).toUpperCase()+mode.slice(1)+" theme")+" selected.";
 }
 $$("[data-theme-choice]").forEach(button=>button.onclick=()=>applyTheme(button.dataset.themeChoice));
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
 $$("[data-settings-section]").forEach(button=>button.onclick=()=>{
  const section=button.dataset.settingsSection;
  $$("[data-settings-section]").forEach(item=>{
   const selected=item===button;
   item.classList.toggle("active",selected);
   if(selected)item.setAttribute("aria-current","page");else item.removeAttribute("aria-current");
  });
  $$("[data-settings-page]").forEach(page=>{
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
  applyWallpaper("alpine",false);
  applyTheme("dark");
  document.body.classList.remove("reduced-motion");
  brightness.value="100";updateBrightness();
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
 maximized=false;snapped=null;$("#windowMax").setAttribute("aria-label","Maximize");
}
function maximizeWindow(){
 if(!maximized&&!snapped)saveRestoreRect();
 clearWindowGeometry();
 win.classList.add("maximized");
 maximized=true;snapped=null;$("#windowMax").setAttribute("aria-label","Restore");
}
function snapWindow(side){
 if(!maximized&&!snapped)saveRestoreRect();
 clearWindowGeometry();
 win.classList.add(side==="left"?"snapped-left":"snapped-right");
 win.style.left=side==="left"?"8px":"calc(50vw + 4px)";
 win.style.top="60px";win.style.width="calc(50vw - 12px)";
 win.style.height="calc(100vh - 90px)";win.style.transform="none";
 snapped=side;maximized=false;$("#windowMax").setAttribute("aria-label","Restore");
}
win.addEventListener("pointerdown",focusWindow);
const titlebar=win.querySelector(".window-titlebar");
titlebar.addEventListener("pointerdown",e=>{
 if(e.target.closest(".window-control")||e.button!==0)return;
 if(maximized||snapped){
  const old=restoreRect;
  clearWindowGeometry();maximized=false;snapped=null;
  win.style.transform="none";
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
 if(!dragging||dragging.pointerId!==e.pointerId)return;
 dragging=null;
 if(e.clientX<=14)snapWindow("left");
 else if(e.clientX>=innerWidth-14)snapWindow("right");
 else{win.classList.remove("snapped-left","snapped-right");snapped=null}
}
titlebar.addEventListener("pointerup",finishDrag);
titlebar.addEventListener("pointercancel",e=>{if(dragging?.pointerId===e.pointerId)dragging=null});
titlebar.addEventListener("dblclick",e=>{
 if(e.target.closest(".window-control"))return;
 if(maximized||snapped)restoreWindow();else maximizeWindow();
});
$("#windowClose").onclick=()=>{win.classList.add("hidden");if(activeApp){window.NexusAppRegistry.unmountApp(activeApp);$$( ".dock-app[data-app='"+activeApp+"']" ).forEach(b=>b.classList.remove("running","minimized"))}activeApp=null};
$("#windowMin").onclick=()=>{win.classList.add("hidden");if(activeApp){$$( ".dock-app[data-app='"+activeApp+"']" ).forEach(b=>b.classList.add("minimized"))}notify("Window minimised")};
$("#windowMax").onclick=()=>{if(maximized||snapped)restoreWindow();else maximizeWindow()};
$("#appSearch").oninput=e=>{const term=e.target.value.toLowerCase();$$(".app-item").forEach(item=>item.style.display=item.textContent.toLowerCase().includes(term)?"flex":"none")};
$$(".app-item").forEach(item=>item.onclick=()=>openApp(item.dataset.app));
if(localStorage.getItem("nexus-wallpaper")==="custom"){restoreCustomWallpaperAtStartup();}else{setDesktopWallpaper(localStorage.getItem("nexus-wallpaper")||"alpine",false);}
const savedAccent=localStorage.getItem("nexus-accent");document.documentElement.style.setProperty("--accent",savedAccent||"#ffad7a");const savedBlur=localStorage.getItem("nexus-blur");document.documentElement.style.setProperty("--blur",(savedBlur||"18")+"px");if(localStorage.getItem("nexus-reduced-motion")==="true")document.body.classList.add("reduced-motion");
const savedTheme=localStorage.getItem("nexus-theme")||"dark";const systemPrefersLight=window.matchMedia&&window.matchMedia("(prefers-color-scheme: light)").matches;desktop.classList.toggle("theme-light",savedTheme==="light"||(savedTheme==="system"&&systemPrefersLight));
})();