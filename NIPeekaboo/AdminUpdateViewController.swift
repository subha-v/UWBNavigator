/*
Admin view controller to update destinations for existing anchor accounts
*/

import UIKit
import Firebase
import FirebaseFirestore

class AdminUpdateViewController: UIViewController {
    
    private let updateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Update Anchor Destinations", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let statusTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = UIColor.systemGray6
        textView.layer.cornerRadius = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Admin: Update Destinations"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(titleLabel)
        view.addSubview(updateButton)
        view.addSubview(statusTextView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            updateButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            updateButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            updateButton.widthAnchor.constraint(equalToConstant: 250),
            updateButton.heightAnchor.constraint(equalToConstant: 50),
            
            statusTextView.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 30),
            statusTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
        updateButton.addTarget(self, action: #selector(updateDestinationsTapped), for: .touchUpInside)
    }
    
    @objc private func updateDestinationsTapped() {
        updateButton.isEnabled = false
        statusTextView.text = "Starting update...\n"
        
        let db = Firestore.firestore()
        
        // Predefined mapping
        let destinationMappings: [(email: String, destination: String, displayName: String)] = [
            ("subhavee1@gmail.com", "window", "Window Anchor"),
            ("akshata@valuenex.com", "kitchen", "Kitchen Anchor"),
            ("elena@valuenex.com", "meeting_room", "Meeting Room Anchor")
        ]
        
        var completedUpdates = 0
        let totalUpdates = destinationMappings.count
        
        for mapping in destinationMappings {
            appendStatus("Processing \(mapping.email)...")
            
            // Find user by email
            db.collection("users")
                .whereField("email", isEqualTo: mapping.email)
                .getDocuments { [weak self] snapshot, error in
                    if let error = error {
                        self?.appendStatus("❌ Error finding \(mapping.email): \(error.localizedDescription)")
                        completedUpdates += 1
                        self?.checkCompletion(completed: completedUpdates, total: totalUpdates)
                        return
                    }
                    
                    guard let documents = snapshot?.documents,
                          let userDoc = documents.first else {
                        self?.appendStatus("⚠️ User not found: \(mapping.email)")
                        completedUpdates += 1
                        self?.checkCompletion(completed: completedUpdates, total: totalUpdates)
                        return
                    }
                    
                    let userId = userDoc.documentID
                    let batch = db.batch()
                    
                    // Update user document
                    let userRef = db.collection("users").document(userId)
                    batch.updateData(["destination": mapping.destination], forDocument: userRef)
                    
                    // Update anchor document
                    let anchorRef = db.collection("anchors").document(userId)
                    batch.updateData([
                        "destination": mapping.destination,
                        "displayName": mapping.displayName
                    ], forDocument: anchorRef)
                    
                    // Commit batch update
                    batch.commit { [weak self] error in
                        if let error = error {
                            self?.appendStatus("❌ Failed to update \(mapping.email): \(error.localizedDescription)")
                        } else {
                            self?.appendStatus("✅ Successfully updated \(mapping.email) → \(mapping.destination)")
                        }
                        completedUpdates += 1
                        self?.checkCompletion(completed: completedUpdates, total: totalUpdates)
                    }
                }
        }
    }
    
    private func appendStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusTextView.text += "\(text)\n"
            // Auto-scroll to bottom
            if let textView = self?.statusTextView {
                let bottom = NSMakeRange(textView.text.count - 1, 1)
                textView.scrollRangeToVisible(bottom)
            }
        }
    }
    
    private func checkCompletion(completed: Int, total: Int) {
        if completed == total {
            DispatchQueue.main.async { [weak self] in
                self?.appendStatus("\n✨ Update process completed!")
                self?.updateButton.isEnabled = true
            }
        }
    }
}