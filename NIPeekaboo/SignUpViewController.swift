/*
See LICENSE folder for this sample's licensing information.

Abstract:
Sign up view controller with role selection.
*/

import UIKit

class SignUpViewController: UIViewController {
    
    // MARK: - UI Components
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Create Account"
        label.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Email"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let displayNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Display Name"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .words
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Password (min 6 characters)"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Confirm Password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let roleLabel: UILabel = {
        let label = UILabel()
        label.text = "Select Your Role:"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let roleSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Navigator", "Anchor"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let roleDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Navigator: Find and navigate to anchor points"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .systemGray
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let destinationLabel: UILabel = {
        let label = UILabel()
        label.text = "Select Anchor Destination:"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let destinationSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Window", "Meeting Room", "Kitchen"])
        control.selectedSegmentIndex = 0
        control.isHidden = true
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let signUpButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign Up", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.title = "Sign Up"
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(titleLabel)
        view.addSubview(emailTextField)
        view.addSubview(displayNameTextField)
        view.addSubview(passwordTextField)
        view.addSubview(confirmPasswordTextField)
        view.addSubview(roleLabel)
        view.addSubview(roleSegmentedControl)
        view.addSubview(roleDescriptionLabel)
        view.addSubview(destinationLabel)
        view.addSubview(destinationSegmentedControl)
        view.addSubview(signUpButton)
        view.addSubview(errorLabel)
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            // Title
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            
            // Email TextField
            emailTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emailTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emailTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            emailTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Display Name TextField
            displayNameTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            displayNameTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 15),
            displayNameTextField.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            displayNameTextField.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            displayNameTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Password TextField
            passwordTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            passwordTextField.topAnchor.constraint(equalTo: displayNameTextField.bottomAnchor, constant: 15),
            passwordTextField.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            passwordTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Confirm Password TextField
            confirmPasswordTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 15),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Role Label
            roleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            roleLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 30),
            
            // Role Segmented Control
            roleSegmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            roleSegmentedControl.topAnchor.constraint(equalTo: roleLabel.bottomAnchor, constant: 15),
            roleSegmentedControl.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            roleSegmentedControl.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            roleSegmentedControl.heightAnchor.constraint(equalToConstant: 44),
            
            // Role Description
            roleDescriptionLabel.topAnchor.constraint(equalTo: roleSegmentedControl.bottomAnchor, constant: 10),
            roleDescriptionLabel.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            roleDescriptionLabel.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            
            // Destination Label
            destinationLabel.topAnchor.constraint(equalTo: roleDescriptionLabel.bottomAnchor, constant: 20),
            destinationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Destination Segmented Control
            destinationSegmentedControl.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: 15),
            destinationSegmentedControl.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            destinationSegmentedControl.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            destinationSegmentedControl.heightAnchor.constraint(equalToConstant: 44),
            
            // Error Label
            errorLabel.topAnchor.constraint(equalTo: destinationSegmentedControl.bottomAnchor, constant: 10),
            errorLabel.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            
            // Sign Up Button
            signUpButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signUpButton.topAnchor.constraint(equalTo: destinationSegmentedControl.bottomAnchor, constant: 30),
            signUpButton.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            signUpButton.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            signUpButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupActions() {
        signUpButton.addTarget(self, action: #selector(signUpButtonTapped), for: .touchUpInside)
        roleSegmentedControl.addTarget(self, action: #selector(roleChanged), for: .valueChanged)
        
        // Dismiss keyboard on tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Actions
    @objc private func signUpButtonTapped() {
        dismissKeyboard()
        errorLabel.isHidden = true
        
        // Validate input
        guard let email = emailTextField.text, !email.isEmpty,
              let displayName = displayNameTextField.text, !displayName.isEmpty,
              let password = passwordTextField.text, !password.isEmpty,
              let confirmPassword = confirmPasswordTextField.text, !confirmPassword.isEmpty else {
            showError("Please fill in all fields")
            return
        }
        
        guard password == confirmPassword else {
            showError("Passwords do not match")
            return
        }
        
        guard password.count >= 6 else {
            showError("Password must be at least 6 characters")
            return
        }
        
        let role: UserRole = roleSegmentedControl.selectedSegmentIndex == 0 ? .navigator : .anchor
        
        // Get selected destination for anchors
        var destination: String? = nil
        if role == .anchor {
            let destinations = ["window", "meeting_room", "kitchen"]
            destination = destinations[destinationSegmentedControl.selectedSegmentIndex]
        }
        
        setLoadingState(true)
        
        FirebaseManager.shared.signUp(email: email, password: password, displayName: displayName, role: role, destination: destination) { [weak self] result in
            DispatchQueue.main.async {
                self?.setLoadingState(false)
                
                switch result {
                case .success(let userId):
                    UserSession.shared.setSession(userId: userId, role: role, displayName: displayName)
                    self?.navigateToRoleBasedScreen(role: role)
                case .failure(let error):
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func roleChanged() {
        if roleSegmentedControl.selectedSegmentIndex == 0 {
            // Navigator selected
            roleDescriptionLabel.text = "Navigator: Find and navigate to anchor points"
            destinationLabel.isHidden = true
            destinationSegmentedControl.isHidden = true
        } else {
            // Anchor selected
            roleDescriptionLabel.text = "Anchor: Serve as a destination point for navigators"
            destinationLabel.isHidden = false
            destinationSegmentedControl.isHidden = false
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Helper Methods
    private func setLoadingState(_ isLoading: Bool) {
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        
        signUpButton.isEnabled = !isLoading
        emailTextField.isEnabled = !isLoading
        displayNameTextField.isEnabled = !isLoading
        passwordTextField.isEnabled = !isLoading
        confirmPasswordTextField.isEnabled = !isLoading
        roleSegmentedControl.isEnabled = !isLoading
    }
    
    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }
    
    private func navigateToRoleBasedScreen(role: UserRole) {
        // Dismiss to root and navigate based on role
        navigationController?.popToRootViewController(animated: false)
        
        if let loginVC = navigationController?.viewControllers.first as? LoginViewController {
            // Use the login view controller's navigation method
            switch role {
            case .anchor:
                let anchorVC = AnchorViewController()
                let navController = UINavigationController(rootViewController: anchorVC)
                navController.modalPresentationStyle = .fullScreen
                loginVC.present(navController, animated: true)
            case .navigator:
                let anchorSelectionVC = AnchorSelectionViewController()
                let navController = UINavigationController(rootViewController: anchorSelectionVC)
                navController.modalPresentationStyle = .fullScreen
                loginVC.present(navController, animated: true)
            }
        }
    }
}