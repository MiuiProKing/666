import AVFoundation
import Combine
import OSLog
import UIKit

@MainActor
final class CameraEngine: ObservableObject {
    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var selectedLensID: CameraLens.ID?
    @Published private(set) var position: CameraPosition = .back
    @Published private(set) var exposureRange: ClosedRange<Float> = -2...2
    @Published private(set) var hasFlash = false
    @Published private(set) var isoRange: ClosedRange<Float> = 50...800
    @Published private(set) var shutterStopsRange: ClosedRange<Float> = -12...0
    @Published private(set) var isManualFocusSupported = false
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isThermallyConstrained = false
    @Published var exposureBias: Float = 0
    @Published var flashMode: FlashMode = .auto
    @Published var isManualMode = false
    @Published var manualISO: Float = 100
    @Published var shutterStops: Float = -8
    @Published var manualFocusPosition: Float = 0.5

    let session = AVCaptureSession()

    var visibleLenses: [CameraLens] {
        availableLenses.filter { $0.position == position }
    }

    private let permissionManager: CameraPermissionProviding
    private let photoLibrary: PhotoLibrarySaving
    private let processor: ImageProcessing
    private let settings: AppSettings
    private let presetStore: PresetStore
    private let sessionQueue = DispatchQueue(
        label: "com.yourname.lumorax.camera.session",
        qos: .userInitiated
    )
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var devicesByID: [String: AVCaptureDevice] = [:]
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var thermalObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.yourname.lumorax", category: "Camera")

    init(
        permissionManager: CameraPermissionProviding,
        photoLibrary: PhotoLibrarySaving,
        processor: ImageProcessing,
        settings: AppSettings,
        presetStore: PresetStore
    ) {
        self.permissionManager = permissionManager
        self.photoLibrary = photoLibrary
        self.processor = processor
        self.settings = settings
        self.presetStore = presetStore
        observeThermalState()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    func start() async {
        var state = permissimºãO-¢G§²ÚîÆ­yÖ÷W&6W2¢òÀ ”"ò¢†÷FôÆ–'&'•6W'f–6Rç7v–gB–â6÷W&6W2¢òÀ ”2ò¢6WGF–æw2ç7v–gB–â6÷W&6W2¢òÀ ”Bò¢6ÖW&&Wf–Wrç7v–gB–â6÷W&6W2¢òÀ ”Rò¢6ÖW&67&VVâç7v–gB–â6÷W&6W2¢òÀ ”bò¢6WGF–æw567&VVâç7v–gB–â6÷W&6W2¢òÀ ’“° —'VäöæÇ”f÷$FWÆ÷–ÖVçE÷7G&ö6W76–ærÒ° —Ó° ”33"ò¢6÷W&6W2¢òÒ° –—6Ò%…6÷W&6W4'V–ÆE†6S° –'V–ÆD7F–öäÖ6²Ò#CsCƒ3cCs° –f–ÆW2Ò€ ”"ò¢&W6WDÖöFVÅFW7G2ç7v–gB–â6÷W&6W2¢òÀ ”2ò¢6WGF–æw5FW7G2ç7v–gB–â6÷W&6W2¢òÀ ’“° —'VäöæÇ”f÷$FWÆ÷–ÖVçE÷7G&ö6W76–ærÒ° —Ó°¢ò¢VæB%…6÷W&6W4'V–ÆE†6R6V7F–öâ¢ğ ¢ò¢&Vv–â%…F&vWDFWVæFVæ7’6V7F–öâ¢ğ ”3Sò¢%…F&vWDFWVæFVæ7’¢òÒ° –—6Ò%…F&vWDFWVæFVæ7“° —F&vWBÒS#ò¢ÅTÔõ$‚¢ó° —F&vWE&÷‡’Ò3ò¢%„6öçF–æW$—FVÕ&÷‡’¢ó° —Ó°¢ò¢VæB%…F&vWDFWVæFVæ7’6V7F–öâ¢ğ ¢ò¢&Vv–â„4'V–ÆD6öæf–wW&F–öâ6V7F–öâ¢ğ ”S3ò¢FV'Vr¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”Åt•5õ4T$4…õU4U%õD…2Òäó° ”4ÄäuôäÅ•¤U%ôäôäåTÄÂÒ”U3° ”4ÄäuôTä$ÄUôÔôETÄU2Ò”U3° ”4ÄäuôTä$ÄUôô$¤5ô$2Ò”U3° ”4Ääuõt$åôDô5TÔTåDD”ôåô4ôÔÔTåE2Ò”U3° ”4õ•õ„4Uõ5E$•Òäó° ”DT%Tuô”ädõ$ÔD”ôåôdõ$ÔBÒGv&c° ”Tä$ÄUõDU5D$”Ä•E’Ò”U3° ”t45ô5ôÄäuTtUõ5DäD$BÒvçSs° ”t45ôõD”Ô•¤D”ôåôÄUdTÂÒ° ”t45õ$U$ô4U54õ%ôDTd”ä•D”ôå2Ò‚$DT%TsÓ"Â"B†–æ†W&—FVB’"Â“° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° ”ÕDÅôTä$ÄUôDT%Tuô”ädòÒ”ä4ÅTDUõ4õU$4S° ”ôäÅ•ô5D•dUô$4‚Ò”U3° •4Dµ$ôõBÒ—†öæV÷3° •5t”eEô5D•dUô4ôÕ”ÄD”ôåô4ôäD•D”ôå2Ò$DT%TrB†–æ†W&—FVB’#° •5t”eEôõD”Ô•¤D”ôåôÄUdTÂÒ"ÔöæöæR#° —Ó° –æÖRÒFV'Vs° —Ó° ”S3"ò¢&VÆV6R¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”Åt•5õ4T$4…õU4U%õD…2Òäó° ”4ÄäuôäÅ•¤U%ôäôäåTÄÂÒ”U3° ”4ÄäuôTä$ÄUôÔôETÄU2Ò”U3° ”4ÄäuôTä$ÄUôô$¤5ô$2Ò”U3° ”4Ääuõt$åôDô5TÔTåDD”ôåô4ôÔÔTåE2Ò”U3° ”4õ•õ„4Uõ5E$•Òäó° ”DT%Tuô”ädõ$ÔD”ôåôdõ$ÔBÒ&Gv&b×v—F‚ÖG7–Ò#° ”Tä$ÄUôå5ô54U%D”ôå2Òäó° ”t45ô5ôÄäuTtUõ5DäD$BÒvçSs° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° ”ÕDÅôTä$ÄUôDT%Tuô”ädòÒäó° •4Dµ$ôõBÒ—†öæV÷3° •5t”eEô4ôÕ”ÄD”ôåôÔôDRÒv†öÆVÖöGVÆS° •dÄ”DDUõ$ôET5BÒ”U3° —Ó° –æÖRÒ&VÆV6S° —Ó° ”S32ò¢FV'Vr¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”54UD4DÄôuô4ôÕ”ÄU%ô”4ôåôäÔRÒ–6öã° ”4ôDUõ4”tåõ5E”ÄRÒWFöÖF–3° ”5U%$TåEõ$ô¤T5EõdU%4”ôâÒ° ”DUdTÄõÔTåEõDTÒÒ"#° ”tTäU$DUô”ädõÄ•5Eôd”ÄRÒ”U3° ””ädõÄ•5Eô´U•ôå46ÖW&W6vTFW67&—F–öâÒ$ÅTÔõ$‚ıí½Í}=]"­Í]2-í½Í­âM½ò­Í­‚Mí-âİ-]Â•†öæRâ#° ””ädõÄ•5Eô´U•ôå5†÷FôÆ–'&'”FEW6vTFW67&—F–öâÒ$ÅTÔõ$‚Mí-½ı]"İı-½RMí-í=M‚"-2Í]M-]­2â#° ””ädõÄ•5Eô´U•õT”Æ–6F–öå66VæTÖæ–fW7EôvVæW&F–öâÒ”U3° ””ädõÄ•5Eô´U•õT”Æ–6F–öå7W÷'G4–æF—&V7D–çWDWfVçG2Ò”U3° ””ädõÄ•5Eô´U•õT”ÆVæ6…67&VVåôvVæW&F–öâÒ”U3° ””ädõÄ•5Eô´U•õT•7W÷'FVD–çFW&f6T÷&–VçFF–öç5ö•†öæRÒ%T”–çFW&f6T÷&–VçFF–öå÷'G&—BT”–çFW&f6T÷&–VçFF–öäÆæG66TÆVgBT”–çFW&f6T÷&–VçFF–öäÆæG66U&–v‡B#° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° ”Ô$´UD”äuõdU%4”ôâÒãã° •$ôET5Eô%TäDÄUô”DTåD”d”U"Ò6öÒç–÷W&æÖRæÇVÖ÷&ƒ° •$ôET5EôäÔRÒ"B…D$tUEôäÔR’#° •5Uõ%DTEõÄDdõ$Õ2Ò&—†öæV÷2—†öæW6–×VÆF÷"#° •5Uõ%E5ôÔ44DÅ•5BÒäó° •5t”eEôTÔ•EôÄô5õ5E$”äu2Ò”U3° •5t”eEõdU%4”ôâÒRã° •D$tUDTEôDUd”4UôdÔ”Å’Ò° —Ó° –æÖRÒFV'Vs° —Ó° ”S3Bò¢&VÆV6R¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”54UD4DÄôuô4ôÕ”ÄU%ô”4ôåôäÔRÒ–6öã° ”4ôDUõ4”tåõ5E”ÄRÒWFöÖF–3° ”5U%$TåEõ$ô¤T5EõdU%4”ôâÒ° ”DUdTÄõÔTåEõDTÒÒ"#° ”tTäU$DUô”ädõÄ•5Eôd”ÄRÒ”U3° ””ädõÄ•5Eô´U•ôå46ÖW&W6vTFW67&—F–öâÒ$ÅTÔõ$‚ıí½Í}=]"­Í]2-í½Í­âM½ò­Í­‚Mí-âİ-]Â•†öæRâ#° ””ädõÄ•5Eô´U•ôå5†÷FôÆ–'&'”FEW6vTFW67&—F–öâÒ$ÅTÔõ$‚Mí-½ı]"İı-½RMí-í=M‚"-2Í]M-]­2â#° ””ädõÄ•5Eô´U•õT”Æ–6F–öå66VæTÖæ–fW7EôvVæW&F–öâÒ”U3° ””ädõÄ•5Eô´U•õT”Æ–6F–öå7W÷'G4–æF—&V7D–çWDWfVçG2Ò”U3° ””ädõÄ•5Eô´U•õT”ÆVæ6…67&VVåôvVæW&F–öâÒ”U3° ””ädõÄ•5Eô´U•õT•7W÷'FVD–çFW&f6T÷&–VçFF–öç5ö•†öæRÒ%T”–çFW&f6T÷&–VçFF–öå÷'G&—BT”–çFW&f6T÷&–VçFF–öäÆæG66TÆVgBT”–çFW&f6T÷&–VçFF–öäÆæG66U&–v‡B#° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° ”Ô$´UD”äuõdU%4”ôâÒãã° •$ôET5Eô%TäDÄUô”DTåD”d”U"Ò6öÒç–÷W&æÖRæÇVÖ÷&ƒ° •$ôET5EôäÔRÒ"B…D$tUEôäÔR’#° •5Uõ%DTEõÄDdõ$Õ2Ò&—†öæV÷2—†öæW6–×VÆF÷"#° •5Uõ%E5ôÔ44DÅ•5BÒäó° •5t”eEôTÔ•EôÄô5õ5E$”äu2Ò”U3° •5t”eEõdU%4”ôâÒRã° •D$tUDTEôDUd”4UôdÔ”Å’Ò° —Ó° –æÖRÒ&VÆV6S° —Ó° ”S3Rò¢FV'Vr¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”%TäDÄUôÄôDU"Ò"B…DU5Eô„õ5B’#° ”4ôDUõ4”tåõ5E”ÄRÒWFöÖF–3° ”tTäU$DUô”ädõÄ•5Eôd”ÄRÒ”U3° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° •$ôET5Eô%TäDÄUô”DTåD”d”U"Ò6öÒç–÷W&æÖRæÇVÖ÷&‚çFW7G3° •$ôET5EôäÔRÒ"B…D$tUEôäÔR’#° •5t”eEõdU%4”ôâÒRã° •D$tUDTEôDUd”4UôdÔ”Å’Ò° •DU5Eô„õ5BÒ"B„%T”ÅEõ$ôET5E5ôD•"’ôÅTÔõ$‚æòB„%TäDÄUôU„T5UD$ÄUôdôÄDU%õD‚’ôÅTÔõ$‚#° —Ó° –æÖRÒFV'Vs° —Ó° ”S3bò¢&VÆV6R¢òÒ° –—6Ò„4'V–ÆD6öæf–wW&F–öã° –'V–ÆE6WGF–æw2Ò° ”%TäDÄUôÄôDU"Ò"B…DU5Eô„õ5B’#° ”4ôDUõ4”tåõ5E”ÄRÒWFöÖF–3° ”tTäU$DUô”ädõÄ•5Eôd”ÄRÒ”U3° ”•„ôäTõ5ôDUÄõ”ÔTåEõD$tUBÒbã° •$ôET5Eô%TäDÄUô”DTåD”d”U"Ò6öÒç–÷W&æÖRæÇVÖ÷&‚çFW7G3° •$ôET5EôäÔRÒ"B…D$tUEôäÔR’#° •5t”eEõdU%4”ôâÒRã° •D$tUDTEôDUd”4UôdÔ”Å’Ò° •DU5Eô„õ5BÒ"B„%T”ÅEõ$ôET5E5ôD•"’ôÅTÔõ$‚æòB„%TäDÄUôU„T5UD$ÄUôdôÄDU%õD‚’ôÅTÔõ$‚#° —Ó° –æÖRÒ&VÆV6S° —Ó°¢ò¢VæB„4'V–ÆD6öæf–wW&F–öâ6V7F–öâ¢ğ ¢ò¢&Vv–â„46öæf–wW&F–öäÆ—7B6V7F–öâ¢ğ ”SCò¢'V–ÆB6öæf–wW&F–öâÆ—7Bf÷"%…&ö¦V7B$ÅTÔõ$‚"¢òÒ° –—6Ò„46öæf–wW&F–öäÆ—7C° –'V–ÆD6öæf–wW&F–öç2Ò€ ”S3ò¢FV'Vr¢òÀ ”S3"ò¢&VÆV6R¢òÀ ’“° –FVfVÇD6öæf–wW&F–öä—5f—6–&ÆRÒ° –FVfVÇD6öæf–wW&F–öäæÖRÒ&VÆV6S° —Ó° ”SC"ò¢'V–ÆB6öæf–wW&F–öâÆ—7Bf÷"%„æF—fUF&vWB$ÅTÔõ$‚"¢òÒ° –—6Ò„46öæf–wW&F–öäÆ—7C° –'V–ÆD6öæf–wW&F–öç2Ò€ ”S32ò¢FV'Vr¢òÀ ”S3Bò¢&VÆV6R¢òÀ ’“° –FVfVÇD6öæf–wW&F–öä—5f—6–&ÆRÒ° –FVfVÇD6öæf–wW&F–öäæÖRÒ&VÆV6S° —Ó° ”SC2ò¢'V–ÆB6öæf–wW&F–öâÆ—7Bf÷"%„æF—fUF&vWB$ÅTÔõ$…FW7G2"¢òÒ° –—6Ò„46öæf–wW&F–öäÆ—7C° –'V–ÆD6öæf–wW&F–öç2Ò€ ”S3Rò¢FV'Vr¢òÀ ”S3bò¢&VÆV6R¢òÀ ’“° –FVfVÇD6öæf–wW&F–öä—5f—6–&ÆRÒ° –FVfVÇD6öæf–wW&F–öäæÖRÒ&VÆV6S° —Ó°¢ò¢VæB„46öæf–wW&F–öäÆ—7B6V7F–öâ¢ğ ¢ò¢&Vv–â„5&VÖ÷FU7v–gE6¶vU&VfW&Væ6R6V7F–öâ¢ğ ”Cò¢„5&VÖ÷FU7v–gE6¶vU&VfW&Væ6R$ÖWFÅWFÂ"¢òÒ° –—6Ò„5&VÖ÷FU7v–gE6¶vU&VfW&Væ6S° —&W÷6—F÷'•U$ÂÒ&‡GG3¢òöv—F‡V"æ6öÒôÖWFÅWFÂôÖWFÅWFÂæv—B#° —&WV—&VÖVçBÒ° –¶–æBÒW†7EfW'6–öã° —fW'6–öâÒã#Rã#° —Ó° —Ó°¢ò¢VæB„5&VÖ÷FU7v–gE6¶vU&VfW&Væ6R6V7F–öâ¢ğ ¢ò¢&Vv–â„57v–gE6¶vU&öGV7DFWVæFVæ7’6V7F–öâ¢ğ ”Cò¢ÖWFÅWFÂ¢òÒ° –—6Ò„57v–gE6¶vU&öGV7DFWVæFVæ7“° —6¶vRÒCò¢„5&VÖ÷FU7v–gE6¶vU&VfW&Væ6R$ÖWFÅWFÂ"¢ó° —&öGV7DæÖRÒÖWFÅWFÃ° —Ó°¢ò¢VæB„57v–gE6¶vU&öGV7DFWVæFVæ7’6V7F–öâ¢ğ —Ó° —&ö÷Dö&¦V7BÒSò¢&ö¦V7Bö&¦V7B¢ó°§Ğ