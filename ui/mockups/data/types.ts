export type ItemState = 'waiting' | 'working' | 'asks' | 'done' | 'done-by-you' | 'not-sent' | 'processing'
export type RouteHow = 'said' | 'screen' | 'followup' | 'only' | 'picked' | 'none'

export interface Crop {
  number: number
  caption: string
}

export interface Item {
  id: string
  project: string | null
  state: ItemState
  title: string
  said: string
  points: number
  age: string
  agent?: string
  note?: string
  how: RouteHow
  followsTitle?: string
  crops: Crop[]
  question?: { text: string; choices: string[] }
}

export interface Project {
  id: string
  name: string
  count: number
  listening: boolean
  folder: string
}
