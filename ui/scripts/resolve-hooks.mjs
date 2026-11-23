import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const appFile = pathToFileURL(join(dirname(fileURLToPath(import.meta.url)), '..', 'package.json')).href

export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context)
  } catch (error) {
    const bare = !specifier.startsWith('.') && !specifier.startsWith('/') && !specifier.startsWith('file:') && !specifier.startsWith('node:')
    if (bare && error && (error.code === 'ERR_MODULE_NOT_FOUND' || error.code === 'ERR_PACKAGE_PATH_NOT_EXPORTED')) {
      return nextResolve(specifier, { ...context, parentURL: appFile })
    }
    throw error
  }
}
