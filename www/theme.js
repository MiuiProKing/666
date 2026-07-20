(() => {
  "use strict";
  const ENABLED_KEY="lumorax_theme_enabled", COLOR_KEY="lumorax_theme_color";
  const LEGACY_ENABLED_KEY="luckyjet_oled_theme", LEGACY_COLOR_KEY="luckyjet_oled_color";
  const presets=["#000000","#0f172a","#22103d","#071f2a","#2a0b12","#2a2107","#f3f4f6"];
  const normalizeColor=value=>/^#[0-9a-f]{6}$/i.test(value||"")?value:"#000000";
  function readState(){
    try{
      const enabledRaw=localStorage.getItem(ENABLED_KEY)??localStorage.getItem(LEGACY_ENABLED_KEY);
      return {enabled:enabledRaw!=="off",color:normalizeColor(localStorage.getItem(COLOR_KEY)||localStorage.getItem(LEGACY_COLOR_KEY))};
    }catch(_error){return {enabled:true,color:"#000000"}}
  }
  function apply(enabled,color,persist=true){
    const safe=normalizeColor(color);
    document.documentElement.classList.toggle("global-theme",Boolean(enabled));
    document.documentElement.classList.toggle("oled-theme",Boolean(enabled));
    document.documentElement.style.setProperty("--global-theme-bg",safe);
    document.documentElement.style.setProperty("--oled-bg",safe);
    const meta=document.getElementById("themeColorMeta");
    if(meta)meta.setAttribute("content",enabled?safe:"#0f1525");
    if(persist)try{
      localStorage.setItem(ENABLED_KEY,enabled?"on":"off");
      localStorage.setItem(COLOR_KEY,safe);
      localStorage.setItem(LEGACY_ENABLED_KEY,enabled?"on":"off");
      localStorage.setItem(LEGACY_COLOR_KEY,safe);
    }catch(_error){}
    document.querySelectorAll("[data-global-theme-toggle]").forEach(input=>input.checked=Boolean(enabled));
    document.querySelectorAll("[data-global-theme-color]").forEach(input=>input.value=safe);
  }
  window.LumoraxTheme={apply,readState};
  const initial=readState();apply(initial.enabled,initial.color,false);
  function mount(){
    if(document.getElementById("globalThemeFab"))return;
    const host=document.createElement("div");
    host.className="global-theme-host";
    host.innerHTML='<button class="global-theme-fab" id="globalThemeFab" type="button" aria-label="App color">🎨</button>'+
      '<section class="global-theme-panel" id="globalThemePanel" aria-hidden="true">'+
      '<div class="global-theme-head"><strong>APP COLOR</strong><button type="button" id="globalThemeClose">×</button></div>'+
      '<label class="global-theme-row"><span>Использовать везде</span><input type="checkbox" data-global-theme-toggle></label>'+
      '<label class="global-theme-row"><span>Свой цвет</span><input type="color" data-global-theme-color></label>'+
      '<div class="global-theme-presets">'+presets.map(color=>'<button type="button" data-theme-preset="'+color+'" style="--swatch:'+color+'" aria-label="'+color+'"></button>').join("")+'</div>'+
      '<small>Включите чистый OLED-чёрный фон или выберите собственный цвет.<br>Идея оформления: IGOledTheme by DeNsor</small></section>';
    document.body.appendChild(host);
    const panel=host.querySelector("#globalThemePanel");
    const open=value=>{panel.classList.toggle("open",value);panel.setAttribute("aria-hidden",value?"false":"true")};
    host.querySelector("#globalThemeFab").addEventListener("click",()=>open(!panel.classList.contains("open")));
    host.querySelector("#globalThemeClose").addEventListener("click",()=>open(false));
    host.querySelector("[data-global-theme-toggle]").addEventListener("change",event=>{const state=readState();apply(event.target.checked,state.color,true)});
    host.querySelector("[data-global-theme-color]").addEventListener("input",event=>{const state=readState();apply(state.enabled,event.target.value,true)});
    host.querySelectorAll("[data-theme-preset]").forEach(button=>button.addEventListener("click",()=>{apply(true,button.dataset.themePreset,true)}));
    const legacyToggle=document.getElementById("oledThemeToggle"),legacyColor=document.getElementById("oledColor");
    if(legacyToggle)legacyToggle.addEventListener("change",()=>apply(legacyToggle.checked,legacyColor?legacyColor.value:readState().color,true));
    if(legacyColor)legacyColor.addEventListener("input",()=>apply(legacyToggle?legacyToggle.checked:true,legacyColor.value,true));
    const state=readState();apply(state.enabled,state.color,false);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mount,{once:true});else mount();
  window.addEventListener("pageshow",()=>{const state=readState();apply(state.enabled,state.color,false)});
})();