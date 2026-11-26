import '@roo/kit/fonts.css'
import '@roo/kit/index.css'
import '@roo/kit/brands/oneroo.css'
import './app.css'
import { createApp } from 'vue'
import App from './App.vue'
import FloatApp from './FloatApp.vue'
import { injectedRoute } from './floatChannel'
import { floatRouteFrom } from './floatRoute'

// A floating panel names its screen (the app injects it, a browser can use #/float/pill); everything else is the main window.
const route = floatRouteFrom(injectedRoute(), window.location.hash)

if (route === undefined) {
  createApp(App).mount('#app')
} else {
  // The kit paints the page colour on :root (base.css), which fills the whole panel behind the card; this class clears it (app.css).
  document.documentElement.classList.add('float-page')
  createApp(FloatApp, { route }).mount('#app')
}
