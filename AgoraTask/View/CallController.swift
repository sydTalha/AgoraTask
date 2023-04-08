//
//  CallController.swift
//  AgoraTask
//
//  Created by Rizwan on 4/4/23.
//

import UIKit
import AgoraRtcKit
import AgoraChat
import AVFoundation
import Speech

class CallController: UIViewController {

    //MARK: - Properties
    var joined: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.callActionBtn.setTitle( self.joined ? "Leave" : "Join", for: .normal)
            }
        }
    }
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    let audioEngine = AVAudioEngine()
    var recognitionRequest : SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask : SFSpeechRecognitionTask?
    
    var agoraEngine: AgoraRtcEngineKit!
    // By default, set the current user role to broadcaster to both send and receive streams.
    var userRole: AgoraClientRole = .broadcaster

    //keys..
    // Update with the App ID of your project generated on Agora Console.
    let appID = "3dfd9c4489df43fbb4dc1db378c8e4eb"
    // Update with the temporary token generated in Agora Console.
    var token = "007eJxTYPB42WPWe6PtodVJnTMyv+bksbs/LptVeih4RZH5ynmbGNMVGIxT0lIsk01MLCxT0kyM05KSTFKSDVOSjM0tki1STVKT5I0NUxoCGRn+nlNhZmSAQBCfmaEkt4CBAQCLZiAt"
//    var token = "007eJxTYJj+tUd744yaU39i9xfGFiUv3j8/hLfTs9XL8oZ6guxiHhEFBuOUtBTLZBMTC8uUNBPjtKQkk5Rkw5QkY3OLZItUk9Qk7016KQ2BjAxvyxYyMjKwMjAyMDGA+AwMALQfHko="
    // Update with the channel name you used to generate the token in Agora Console.
    var channelName = "tmp"
    var msgToSend: String?
    let speechSynthesizer = AVSpeechSynthesizer()

    
    //MARK: - IBOutlets
    
    @IBOutlet weak var callActionBtn: UIButton!
    
    @IBOutlet weak var msgLbl: UILabel!
    
    @IBOutlet weak var userIDTxtField: UITextField!
    
    @IBOutlet weak var tokenTxtField: UITextField!
    
    @IBOutlet weak var receiverUserIDTxtField: UITextField!
    
    //MARK: - IBActions
    
    
    
    //MARK: - Handlers
    @objc func dismissKeyboard() {
        //Causes the view (or one of its embedded text fields) to resign the first responder status.
        view.endEditing(true)
    }
    
    
    @objc func buttonAction(sender: UIButton!) {
        if userIDTxtField.text != "" || receiverUserIDTxtField.text != ""{
            self.loginAction {
                if !self.joined {
                    sender.isEnabled = false
                    DispatchQueue.global(qos: .userInitiated).async {
                        print("starting STT")
                        if self.audioEngine.isRunning {
                            self.audioEngine.stop()
                            self.recognitionRequest?.endAudio()
                            print("Start Recording")
        //                    self.btnStart.isEnabled = false
        //                    self.btnStart.setTitle("Start Recording", for: .normal)
                        } else {
                            try? self.startRecording()
                            print("Stop Recording")
        //                    self.btnStart.setTitle("Stop Recording", for: .normal)
                        }
                        Task {

                            await self.joinChannel()
                            sender.isEnabled = true
                        }
                    }
                    
                    
                    
                } else {
                    self.logoutAction()
                    self.leaveChannel()
                }

            }
        }
        else{
            showMessage(title: "Enter User ID", text: "Please Enter Correct User ID")
        }
        
    }
    
    

}

//MARK: - Lifecycle
extension CallController{
    override func viewDidLoad() {
        super.viewDidLoad()
        self.initViews()
        self.initializeAgoraEngine()
        
        speechRecognizer?.delegate = self

        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                print("Speech recognition authorized")
            case .denied:
                print("Speech recognition denied")
            case .restricted:
                print("Speech recognition restricted")
            case .notDetermined:
                print("Speech recognition not determined")
            @unknown default:
                fatalError()
            }
        }
        
        initChatSDK()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIInputViewController.dismissKeyboard))

        //Uncomment the line below if you want the tap not not interfere and cancel other interactions.
        //tap.cancelsTouchesInView = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .duckOthers])
        } catch {
            print("Failed to set audio session category.")
        }
        
        view.addGestureRecognizer(tap)
    }
    
   
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        leaveChannel()
        DispatchQueue.global(qos: .userInitiated).async {AgoraRtcEngineKit.destroy()}
    }
}


//MARK: - Interface Setup
extension CallController{
    func initializeAgoraEngine() {
        let config = AgoraRtcEngineConfig()
        // Pass in your App ID here.
        config.appId = appID
        // Use AgoraRtcEngineDelegate for the following delegate parameter.
        agoraEngine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        agoraEngine.adjustRecordingSignalVolume(2)
    }
    
    func initChatSDK() {
        // Replaces <#Agora App Key#> with your own App Key.
        // Initializes the Agora Chat SDK.
        let options = AgoraChatOptions(appkey: "61303894#1099602")
        options.isAutoLogin = false // Disables auto login.
        options.enableConsoleLog = true
        AgoraChatClient.shared.initializeSDK(with: options)
        // Adds the chat delegate to receive messages.
        AgoraChatClient.shared.chatManager?.add(self, delegateQueue: nil)
    }
    
    
    func initViews() {
        callActionBtn.setTitle("Join", for: .normal)

        callActionBtn.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
        self.view.addSubview(callActionBtn)
    }
}


//MARK: - Agora Voice
extension CallController{
    func joinChannel() async {
        if await !self.checkForPermissions() {
            showMessage(title: "Error", text: "Permissions were not granted")
            return
        }
        
        let option = AgoraRtcChannelMediaOptions()

        // Set the client role option as broadcaster or audience.
        if self.userRole == .broadcaster {
            option.clientRoleType = .broadcaster
        } else {
            option.clientRoleType = .audience
        }

        // For an audio call scenario, set the channel profile as communication.
        option.channelProfile = .communication

        // Join the channel with a temp token and channel name
        let result = agoraEngine.joinChannel(
            byToken: token, channelId: channelName, uid: 0, mediaOptions: option,
            joinSuccess: { (channel, uid, elapsed) in }
        )

        // Check if joining the channel was successful and set joined Bool accordingly
        if (result == 0) {
            joined = true
            showMessage(title: "Success", text: "Successfully joined the channel as \(self.userRole)")
            
        }
        
    }

    func leaveChannel() {
        let result = agoraEngine.leaveChannel(nil)
        // Check if leaving the channel was successful and set joined Bool accordingly
        if result == 0 { joined = false }
    }

    
    
}

//MARK: - Agora Chat
extension CallController{
    func loginAction(completion: @escaping ()->()) {
        guard let userId = self.userIDTxtField.text,
              let token = self.tokenTxtField.text else {
            print("userId or token is empty")
            return
        }
        let err = AgoraChatClient.shared.login(withUsername: userId, agoraToken: token)
        if err == nil {
            print("login success")
            completion()
            
        } else {
            print("login failed:\(err?.errorDescription ?? "")")
        }
    }
    
    func logoutAction() {
        AgoraChatClient.shared.logout(false) { err in
            if err == nil {
                print("logout success")
            }
        }
    }
    
    // Sends a text message.
    func sendAction() {
        print("userid: \(receiverUserIDTxtField.text)", "msg: \(msgToSend)")
        guard let remoteUser = receiverUserIDTxtField.text,
              let text = msgToSend,
              let currentUserName = AgoraChatClient.shared.currentUsername else {
            print("Not login or remoteUser/text is empty")
            return
        }
        let msg = AgoraChatMessage(
            conversationId: remoteUser, from: currentUserName,
            to: remoteUser, body: .text(content: text), ext: nil
        )
        AgoraChatClient.shared.chatManager?.send(msg, progress: nil) { msg, err in
            if let err = err {
                print("send msg error.\(err.errorDescription)")
            } else {
                print("send msg success")
            }
        }
    }
}

//MARK: - STT and TTS
extension CallController{
    func startRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(AVAudioSession.Category.record)
        try audioSession.setMode(AVAudioSession.Mode.measurement)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode

        recognitionRequest.shouldReportPartialResults = true

        var recognitionTask: SFSpeechRecognitionTask?

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { result, error in
            var isFinal = false

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print(transcription)
                
                self.msgToSend = transcription
                self.sendAction()
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                recognitionTask = nil
            }
        })

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

    }
    
    func speak(_ text: String) {
        let speechUtterance = AVSpeechUtterance(string: text)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.volume = 1.0
        speechUtterance.rate = 0.5 // adjust the speaking rate as needed
        speechSynthesizer.speak(speechUtterance)
    }
}

//MARK: - Helpers
extension CallController{
    func checkForPermissions() async -> Bool {
        let hasPermissions = await self.avAuthorization(mediaType: .audio)
        return hasPermissions
    }

    func avAuthorization(mediaType: AVMediaType) async -> Bool {
        let mediaAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch mediaAuthorizationStatus {
        case .denied, .restricted: return false
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }
    
    func showMessage(title: String, text: String, delay: Int = 2) -> Void {
        let deadlineTime = DispatchTime.now() + .seconds(delay)
        DispatchQueue.main.asyncAfter(deadline: deadlineTime, execute: {
            let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
            self.present(alert, animated: true)
            alert.dismiss(animated: true, completion: nil)
        })
    }
}

//MARK: - AgoraRtcEngineDelegate
extension CallController: AgoraRtcEngineDelegate{
    // Callback called when a new host joins the channel
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        
    }
}

//MARK: - AgoraChatManagerDelegate
extension CallController: AgoraChatManagerDelegate{
    
    func messagesDidReceive(_ aMessages: [AgoraChatMessage]) {
        
        for msg in aMessages {
            print("msg body type: \(msg.body)")
            switch msg.swiftBody {
            case let .text(content):
                print("receive text msg,content: \(content)")
                self.msgLbl.text = content
                print("speaking...")
                self.speak(content)
                
                
            default:
                break
            }
        }
    }
}

//MARK: - SFSpeechRecognizerDelegate
extension CallController: SFSpeechRecognizerDelegate{
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        
    }
}
