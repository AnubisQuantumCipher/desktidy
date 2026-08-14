import Foundation

// ============================================================================
//  DeskTidy — configuration
//
//  This is the ONLY file most people need to touch. Edit the values below,
//  then re-run  ./install.sh  to rebuild and reload. Nothing here phones home.
// ============================================================================

enum Config {

    /// The folder DeskTidy watches and keeps organized. Default: your Desktop.
    /// (Relative to your home folder. You can also point DeskTidy at a different
    ///  folder without editing this — set the DESKTIDY_TARGET_DIR env var.)
    static let targetDirName = "Desktop"

    /// How long (seconds) a file must sit still before DeskTidy moves it.
    /// This is what stops it grabbing a file mid-download or mid-save.
    static let settleSeconds: TimeInterval = 15

    /// Version of the deterministic routing policy. Recorded in every movement
    /// receipt so history stays interpretable if rules change. Bump when any
    /// routing rule or extension set below changes meaning.
    static let routingPolicyVersion = "1"

    // -- Folder names -------------------------------------------------------
    // Rename these to whatever you like. DeskTidy creates each folder on demand
    // (only when something actually needs it) and never touches these folders
    // themselves while sorting.
    static let folderInbox       = "Inbox"        // anything DeskTidy can't confidently place
    static let folderDocuments   = "Documents"
    static let folderImages      = "Images"
    static let folderScreenshots = "Screenshots"
    static let folderVideos      = "Videos"
    static let folderAudio       = "Audio"
    static let folderArchives    = "Archives"
    static let folderCode        = "Code"
    static let folderFolders     = "Folders"      // where dropped sub-folders go

    // -- File-type routing (by lowercased extension) ------------------------
    // Move an extension between sets to change where that type goes. Keep the
    // sets disjoint (an extension should appear in only one).
    static let imageExts:    Set<String> = ["png","jpg","jpeg","gif","heic","heif","tiff","tif","webp","bmp","svg","ico"]
    static let videoExts:    Set<String> = ["mp4","mov","m4v","mkv","webm","avi","flv","wmv","mpg","mpeg"]
    static let audioExts:    Set<String> = ["mp3","wav","aiff","aif","m4a","flac","aac","ogg","wma"]
    static let archiveExts:  Set<String> = ["zip","tar","gz","tgz","bz2","xz","7z","rar","dmg","pkg","iso"]
    static let documentExts: Set<String> = ["pdf","doc","docx","txt","rtf","md","markdown","pages","odt","key",
                                             "ppt","pptx","xls","xlsx","csv","tsv","numbers","epub","mobi","azw3"]
    static let codeExts:     Set<String> = ["js","jsx","ts","tsx","py","rb","go","rs","c","h","cpp","hpp","cc","cs",
                                             "java","kt","swift","php","sh","zsh","bash","sql","json","yaml","yml",
                                             "toml","xml","html","htm","css","scss","less","ipynb","r","lua","pl","pm",
                                             "m","mm","vue","svelte"]

    // -- Optional on-device AI triage ---------------------------------------
    // When true AND you're on macOS 26+ (Apple Intelligence), DeskTidy uses
    // Apple's on-device model to *suggest* homes for anything left in Inbox.
    // It is SUGGESTIONS ONLY — the model never moves, renames, or deletes a
    // file, and nothing leaves your Mac. On older macOS this is simply skipped.
    static let enableSmartTriage = true
    static let smartIntervalSeconds: TimeInterval = 300
}

// Where a file belongs. Folder names come from Config above (user-editable).
// Lives here (not in the engine file) so lightweight targets — the CLI and the
// R1A menu-bar app — share one definition without importing the engine's @main.
enum Category: CaseIterable {
    case inbox, documents, images, screenshots, videos, audio, archives, code, folders

    var folderName: String {
        switch self {
        case .inbox:       return Config.folderInbox
        case .documents:   return Config.folderDocuments
        case .images:      return Config.folderImages
        case .screenshots: return Config.folderScreenshots
        case .videos:      return Config.folderVideos
        case .audio:       return Config.folderAudio
        case .archives:    return Config.folderArchives
        case .code:        return Config.folderCode
        case .folders:     return Config.folderFolders
        }
    }
}

enum DeskTidyVersion { static let string = "v1.2.0" }
