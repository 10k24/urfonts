import Foundation

if Headless.isRequested {
    Headless.run()
} else {
    UrFontsApp.main()
}
