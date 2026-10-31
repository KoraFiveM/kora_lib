-- `provide 'screenshot-basic'` only satisfies dependency checks. This late
-- hook (after modules/** has populated Kora.screenshot and exports.lua has
-- created Kora.compat.provideExport) preserves the resource identity that
-- existing clients use: exports['screenshot-basic']:requestScreenshot(...).
Kora.compat.provideExport('screenshot-basic', 'requestScreenshot', Kora.screenshot.requestScreenshot)
Kora.compat.provideExport('screenshot-basic', 'requestScreenshotUpload', Kora.screenshot.requestScreenshotUpload)
