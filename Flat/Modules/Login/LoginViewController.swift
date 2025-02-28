//
//  LoginViewController.swift
//  flat
//
//  Created by xuyunshi on 2021/10/13.
//  Copyright © 2021 agora.io. All rights reserved.
//

import AuthenticationServices
import SafariServices
import UIKit

class LoginViewController: UIViewController {
    @IBOutlet var tipsLabel: UILabel!
    @IBOutlet var smsAuthView: SMSAuthView!
    @IBOutlet var loginButton: FlatGeneralCrossButton!
    var weChatLogin: WeChatLogin?
    var githubLogin: GithubLogin?
    @IBOutlet var flatLabel: UILabel!
    var appleLogin: Any?
    var lastLoginPhone: String? {
        get {
            UserDefaults.standard.value(forKey: "lastLoginPhone") as? String
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "lastLoginPhone")
        }
    }

    var deviceAgreementAgree: Bool {
        get {
            UserDefaults.standard.value(forKey: "deviceAgreementAgree") as? Bool ?? false
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "deviceAgreementAgree")
            if newValue {
                startGoogleAnalytics()
            }
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if traitCollection.verticalSizeClass == .compact || traitCollection.horizontalSizeClass == .compact {
            return .portrait
        } else {
            return .all
        }
    }

    deinit {
        logger.trace("\(self) deinit")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !deviceAgreementAgree {
            showDeviceAgreeAlert()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        loadHistory()
        bind()
        #if DEBUG
            let debugSelector = #selector(debugLogin(sender:))
            if responds(to: debugSelector) {
                let doubleTap = UITapGestureRecognizer(target: self, action: debugSelector)
                doubleTap.numberOfTapsRequired = 2
                view.addGestureRecognizer(doubleTap)
            }
        #endif
    }

    // MARK: - Action

    @objc
    func onClickLogin(sender: UIButton) {
        if case let .failure(errStr) = smsAuthView.allValidCheck(sender: sender) {
            toast(errStr)
            return
        }
        let request = PhoneLoginRequest(phone: smsAuthView.fullPhoneText, code: smsAuthView.codeText)
        let activity = showActivityIndicator()
        ApiProvider.shared.request(fromApi: request) { [weak self] result in
            activity.stopAnimating()
            switch result {
            case let .success(user):
                self?.lastLoginPhone = self?.smsAuthView.phoneTextfield.text
                AuthStore.shared.processLoginSuccessUserInfo(user)
            case let .failure(error):
                self?.toast(error.localizedDescription)
            }
        }
    }

    // MARK: - Private

    func setupViews() {
        stackView.arrangedSubviews.forEach {
            $0.backgroundColor = .color(type: .background)
        }
        flatLabel.textColor = .color(type: .text, .strong)

        // Hide weChat login when weChat not installed
        weChatLoginButton.isHidden = !WXApi.isWXAppInstalled()
        syncTraitCollection(traitCollection)
        setupAppleLogin()
        view.addSubview(agreementCheckStackView)
        agreementCheckStackView.snp.makeConstraints { make in
            make.centerX.equalTo(horizontalLoginTypesStackView)
            make.top.equalTo(loginButton.snp.bottom).offset(8)
        }

        tipsLabel.textColor = .color(type: .text)
        tipsLabel.adjustsFontSizeToFitWidth = true
        tipsLabel.minimumScaleFactor = 0.7
    }

    func loadHistory() {
        smsAuthView.phoneTextfield.text = lastLoginPhone
    }

    func showDeviceAgreeAlert() {
        let vc = PrivacyAlertViewController(
            agreeClick: { [unowned self] in
                self.dismiss(animated: false)
                self.deviceAgreementAgree = true
            },
            cancelClick: {
                exit(0)
            },
            alertTitle: localizeStrings("Service and privacy"),
            agreeTitle: localizeStrings("Agree and continue"),
            rejectTitle: localizeStrings("Disagree and exit"),
            attributedString: agreementAttributedString()
        )
        vc.clickEmptyToCancel = false
        present(vc, animated: true)
    }

    func bind() {
        smsAuthView.loginEnable
            .asDriver(onErrorJustReturn: true)
            .drive(loginButton.rx.isEnabled)
            .disposed(by: rx.disposeBag)

        smsAuthView.additionalCheck = { [weak self] sender in
            guard let self else { return .failure("") }
            let agree = self.checkAgreementDidAgree()
            if agree { return .success(()) }
            self.showAgreementCheckAlert { [weak self, weak sender] in
                guard let self,
                      let sender = sender as? UIButton
                else { return }
                self.smsAuthView.onClickSendSMS(sender: sender)
            }
            return .failure("")
        }
        smsAuthView.countryCodeClick = { [weak self] in
            self?.presentCountryPicker()
        }

        smsAuthView.smsRequestMaker = { phone in
            ApiProvider.shared.request(fromApi: SMSRequest(scenario: .login, phone: phone))
        }

        loginButton.addTarget(self, action: #selector(onClickLogin(sender:)), for: .touchUpInside)
    }

    func presentCountryPicker() {
        let picker = CountryCodePicker()
        picker.pickingHandler = { [weak self] country in
            self?.dismiss(animated: true)
            self?.smsAuthView.country = country
        }
        let navi = BaseNavigationViewController(rootViewController: picker)
        navi.modalPresentationStyle = .formSheet
        present(navi, animated: true)
    }
    
    func showAgreementCheckAlert(agreeAction: (() -> Void)? = nil) {
        let vc = PrivacyAlertViewController(
            agreeClick: { [unowned self] in
                self.dismiss(animated: false)
                self.agreementCheckButton.isSelected = true
                agreeAction?()
            },
            cancelClick: { [unowned self] in
                self.dismiss(animated: false)
            },
            alertTitle: localizeStrings("Service and privacy"),
            agreeTitle: localizeStrings("Have read and agree"),
            rejectTitle: localizeStrings("Reject"),
            attributedString: agreementAttributedString1()
        )
        present(vc, animated: true)
    }

    func checkAgreementDidAgree() -> Bool {
        agreementCheckButton.isSelected
    }

    func syncTraitCollection(_ trait: UITraitCollection) {
        if trait.horizontalSizeClass == .compact || trait.verticalSizeClass == .compact {
            loginBg.isHidden = true
        } else {
            loginBg.isHidden = false
        }
    }

    func setupAppleLogin() {
        let container = UIView()
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .default, authorizationButtonStyle: .black)
        container.addSubview(button)
        horizontalLoginTypesStackView.addArrangedSubview(container)
        button.addTarget(self, action: #selector(onClickAppleLogin(sender: )), for: .touchUpInside)

        button.cornerRadius = 29
        button.removeConstraints(button.constraints)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(58)
            make.center.equalToSuperview()
        }
    }

    @objc func onClickAppleLogin(sender: UIButton) {
        guard checkAgreementDidAgree() else {
            showAgreementCheckAlert() { [weak self] in
                self?.onClickAppleLogin(sender: sender)
            }
            return
        }
        showActivityIndicator()
        appleLogin = AppleLogin()
        (appleLogin as! AppleLogin).startLogin(sender: sender) { [weak self] result in
            self?.stopActivityIndicator()
            switch result {
            case .success:
                return
            case let .failure(error):
                self?.showAlertWith(message: error.localizedDescription.isEmpty ? localizeStrings("Login fail") : error.localizedDescription)
            }
        }
    }

    @IBAction func onClickWeChatButton() {
        guard checkAgreementDidAgree() else {
            showAgreementCheckAlert() { [weak self] in
                self?.onClickWeChatButton()
            }
            return
        }
        guard let launchCoordinator = globalLaunchCoordinator else { return }
        showActivityIndicator(forSeconds: 1)
        weChatLogin?.removeLaunchItemFromLaunchCoordinator?()
        weChatLogin = WeChatLogin()
        weChatLogin?.startLogin(withAuthStore: AuthStore.shared,
                                launchCoordinator: launchCoordinator) { [weak self] result in
            switch result {
            case let .success(user):
                logger.info("weChat login user: \(user.name) \(user.userUUID)")
                return
            case let .failure(error):
                self?.showAlertWith(message: error.localizedDescription.isEmpty ? localizeStrings("Login fail") : error.localizedDescription)
            }
        }
    }

    @IBAction func onClickGithubButton(sender: UIButton) {
        guard checkAgreementDidAgree() else {
            showAgreementCheckAlert() { [weak self] in
                self?.onClickGithubButton(sender: sender)
            }
            return
        }
        guard let coordinator = globalLaunchCoordinator else { return }
        showActivityIndicator(forSeconds: 1)
        githubLogin?.removeLaunchItemFromLaunchCoordinator?()
        githubLogin = GithubLogin()
        githubLogin?.startLogin(withAuthStore: AuthStore.shared,
                                launchCoordinator: coordinator,
                                sender: sender,
                                completionHandler: { [weak self] result in
                                    switch result {
                                    case .success:
                                        return
                                    case let .failure(error):
                                        self?.showAlertWith(message: error.localizedDescription)
                                    }
                                })
    }

    @objc func onClickAgreement(sender: UIButton) {
        sender.isSelected = !sender.isSelected
    }

    @objc func onClickPrivacy() {
        let controller = SFSafariViewController(url: .init(string: "https://flat.whiteboard.agora.io/privacy.html")!)
        present(controller, animated: true, completion: nil)
    }

    @objc func onClickServiceAgreement() {
        let controller = SFSafariViewController(url: .init(string: "https://flat.whiteboard.agora.io/service.html")!)
        present(controller, animated: true, completion: nil)
    }

    @IBOutlet var horizontalLoginTypesStackView: UIStackView!
    @IBOutlet var loginBg: UIView!
    @IBOutlet var stackView: UIStackView!
    @IBOutlet var githubLoginButton: UIButton!
    @IBOutlet var weChatLoginButton: UIButton!

    // MARK: Lazy

    lazy var agreementCheckButton: UIButton = {
        let btn = UIButton.checkBoxStyleButton()
        btn.setTitleColor(.color(type: .text), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12)
        btn.setTitle("  " + localizeStrings("Have read and agree") + " ", for: .normal)
        btn.addTarget(self, action: #selector(onClickAgreement), for: .touchUpInside)
        btn.contentEdgeInsets = .init(top: 8, left: 8, bottom: 8, right: 0)
        return btn
    }()

    lazy var agreementCheckStackView: UIStackView = {
        let privacyButton = UIButton(type: .custom)
        privacyButton.tintColor = .color(type: .primary)
        privacyButton.setTitleColor(.color(type: .primary), for: .normal)
        privacyButton.titleLabel?.font = .systemFont(ofSize: 12)
        privacyButton.setTitle(localizeStrings("Privacy Policy"), for: .normal)
        privacyButton.addTarget(self, action: #selector(onClickPrivacy), for: .touchUpInside)

        let serviceAgreementButton = UIButton(type: .custom)
        serviceAgreementButton.tintColor = .color(type: .primary)
        serviceAgreementButton.titleLabel?.font = .systemFont(ofSize: 12)
        serviceAgreementButton.setTitle(localizeStrings("Service Agreement"), for: .normal)
        serviceAgreementButton.setTitleColor(.color(type: .primary), for: .normal)
        serviceAgreementButton.addTarget(self, action: #selector(onClickServiceAgreement), for: .touchUpInside)

        let label1 = UILabel()
        label1.textColor = .color(type: .text)
        label1.font = .systemFont(ofSize: 12)
        label1.text = " " + localizeStrings("and") + " "
        let view = UIStackView(arrangedSubviews: [agreementCheckButton, privacyButton, label1, serviceAgreementButton])
        view.axis = .horizontal
        view.distribution = .fill
        return view
    }()
}
