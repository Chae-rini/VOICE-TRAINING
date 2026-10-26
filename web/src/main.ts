import { mount } from 'svelte'
import App from './App.svelte'
import './app.css'
import { isNativeApp } from './platform/app'
import { installNativeApp } from './platform/nativeApp'

if (isNativeApp()) installNativeApp()
mount(App, { target: document.getElementById('app')! })
