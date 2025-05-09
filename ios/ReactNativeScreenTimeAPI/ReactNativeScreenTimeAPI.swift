//
//  ReactNativeScreenTimeAPI.swift
//  ReactNativeScreenTimeAPI
//
//  Created by noodleofdeath on 2/16/24.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import ScreenTime

import SwiftUI

let IMAGE_GEN_SLEEP_INTERVAL_MICROSECONDS: UInt32 = 1000000/5

struct RNTFamilyActivityPickerView: View {
  @State var model = ScreenTimeAPI.shared
  
  let headerText: String
  let footerText: String
  
  init(activitySelection _: FamilyActivitySelection? = nil,
       headerText: String = "",
       footerText: String = "")
  {
    self.headerText = headerText
    self.footerText = footerText
  }
  
  var body: some View {
    FamilyActivityPicker(headerText: headerText,
                         footerText: footerText,
                         selection: $model.activitySelection)
  }
}

struct RNTFamilyActivityPickerModalView: View {
  @Environment(\.presentationMode) var presentationMode
  
  @State var activitySelection: FamilyActivitySelection
  
  let title: String
  let headerText: String
  let footerText: String
  let onDismiss: (_ selection: NSDictionary?) -> Void
  
  init(activitySelection: FamilyActivitySelection? = nil,
       title: String = "",
       headerText: String = "",
       footerText: String = "",
       onDismiss: @escaping (_ selection: NSDictionary?) -> Void)
  {
    _activitySelection = State(initialValue: activitySelection ?? ScreenTimeAPI.shared.activitySelection)
    self.title = title
    self.headerText = headerText
    self.footerText = footerText
    self.onDismiss = onDismiss
  }
  
  var cancelButton: some View {
    Button("Cancel") {
      presentationMode.wrappedValue.dismiss()
      onDismiss(nil)
    }
  }
  
  var doneButton: some View {
    Button("Done") {
      presentationMode.wrappedValue.dismiss()
      onDismiss(activitySelection.encoded)
    }
  }
  
  var body: some View {
    NavigationView {
      VStack {
        FamilyActivityPicker(headerText: headerText,
                             footerText: footerText,
                             selection: $activitySelection)
      }
      .navigationBarItems(leading: cancelButton, trailing: doneButton)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

@objc(RNTFamilyActivityPickerViewFactory)
public class RNTFamilyActivityPickerViewFactory: NSObject {
  @objc public static func view() -> UIView {
    let view = RNTFamilyActivityPickerView()
    let vc = UIHostingController(rootView: view)
    return vc.view
  }
}


@objc(ScreenTimeAPI)
public class ScreenTimeAPI: NSObject {
  
  public static let shared = ScreenTimeAPI()
  
  lazy var store: ManagedSettingsStore = {
    let store = ManagedSettingsStore()
    store.application.denyAppRemoval = true
    return store
  }()
  
  var activitySelection = FamilyActivitySelection() {
    willSet(value) {
      store.shield.applications = value.applicationTokens.isEmpty ? nil : value.applicationTokens
      store.shield.applicationCategories =
      ShieldSettings.ActivityCategoryPolicy.specific(value.categoryTokens, except: Set())
      store.shield.webDomains = value.webDomainTokens
      store.shield.webDomainCategories =
      ShieldSettings.ActivityCategoryPolicy.specific(value.categoryTokens, except: Set())
    }
  }
  
  @objc
  static func requiresMainQueueSetup() -> Bool { return true }
  
  // managed settings
  
  @objc
  public func getAuthorizationStatus(_ resolve: @escaping RCTPromiseResolveBlock,
                                     rejecter reject: @escaping RCTPromiseRejectBlock)
  {
    let _ = AuthorizationCenter.shared.$authorizationStatus.sink {
      switch $0 {
      case .notDetermined:
        resolve("notDetermined")
      case .denied:
        resolve("denied")
      case .approved:
        resolve("approved")
      @unknown default:
        reject("0", "Unhandled Authorization Status Type", nil)
      }
    }
  }
  
  @objc
  public func getStore(_ resolve: RCTPromiseResolveBlock? = nil,
                       rejecter _: RCTPromiseRejectBlock? = nil)
  {
    resolve?(store.encoded)
  }
  
  @objc
  public func getActivitySelection(_ resolve: RCTPromiseResolveBlock? = nil,
                                   rejecter _: RCTPromiseRejectBlock? = nil)
  {
    resolve?(activitySelection.encoded)
  }
  
  @objc
  public func setActivitySelection(_ selectionDict: NSDictionary,
                                   resolver resolve: RCTPromiseResolveBlock? = nil,
                                   rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    if let selection = FamilyActivitySelection.from(selectionDict) { // 'selection' is the native FamilyActivitySelection object
      activitySelection = selection

      // --- ADDED CODE: Save to App Group UserDefaults ---
      let appGroupId = "group.com.allinaigc.PrayToUnlock" // Your App Group ID
      let userDefaultsKey = "shieldedSelection"        // Key used by your PrayToUnlockMonitor extension

      if let userDefaults = UserDefaults(suiteName: appGroupId) {
          do {
              let encoder = JSONEncoder()
              // FamilyActivitySelection from Apple's SDK is already Codable.
              let selectionData = try encoder.encode(selection) 
              userDefaults.set(selectionData, forKey: userDefaultsKey)
              print("RNScreenTimeAPI: Successfully saved FamilyActivitySelection to App Group UserDefaults for key '\(userDefaultsKey)' in group '\(appGroupId)'.")
          } catch {
              print("RNScreenTimeAPI: Failed to encode or save FamilyActivitySelection to App Group UserDefaults: \(error)")
              // Decide if this failure should be reported back to JS, e.g., by calling reject
              // For now, it just prints the error to the native console.
          }
      } else {
          print("RNScreenTimeAPI: Error: Could not access App Group UserDefaults. App Group ID: \(appGroupId). Is the App Group configured correctly for the main app target?")
          // Decide if this failure should be reported back to JS
      }
      // --- END OF ADDED CODE ---

      resolve?(nil)
      return
    }
    reject?("0", "unable to parse selection", nil)
  }
  
  @objc
  public func clearActivitySelection() {
    activitySelection = FamilyActivitySelection()
  }
  
  @objc
  public func requestAuthorization(_ memberName: String,
                                   resolver resolve: RCTPromiseResolveBlock? = nil,
                                   rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    guard let member: FamilyControlsMember =
            memberName == "child" ? .child :
              memberName == "individual" ? .individual : nil
    else {
      reject?("0", "invalid member type", nil)
      return
    }
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: member)
        resolve?(nil)
      } catch {
        reject?("0", error.localizedDescription, nil)
        print(error)
      }
    }
  }
  
  @objc
  public func revokeAuthorization(_ resolve: RCTPromiseResolveBlock? = nil,
                                  rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    AuthorizationCenter.shared.revokeAuthorization {
      do {
        try $0.get()
        resolve?(nil)
      } catch {
        reject?("0", error.localizedDescription, nil)
      }
    }
  }
  
  @objc
  public func denyAppRemoval() {
    store.application.denyAppRemoval = true
  }
  
  @objc
  public func allowAppRemoval() {
    store.application.denyAppRemoval = false
  }
  
  @objc
  public func denyAppInstallation() {
    store.application.denyAppInstallation = true
  }
  
  @objc
  public func allowAppInstallation() {
    store.application.denyAppInstallation = false
  }
  
  @objc
  public func initializeMonitoring(_ startTimestamp: String = "00:00",
                                   end endTimestamp: String = "23:59",
                                   resolver resolve: RCTPromiseResolveBlock? = nil,
                                   rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    do {
      guard let start = DateFormatter().date(from: startTimestamp),
            let end = DateFormatter().date(from: endTimestamp)
      else {
        reject?("0", "invalid date provided", nil)
        return
      }
      let scheduleStart = Calendar.current.dateComponents([.hour, .minute], from: start)
      let scheduleEnd = Calendar.current.dateComponents([.hour, .minute], from: end)
      let schedule: DeviceActivitySchedule = .init(intervalStart: scheduleStart,
                                                   intervalEnd: scheduleEnd,
                                                   repeats: true,
                                                   warningTime: nil)
      let center: DeviceActivityCenter = .init()
      try center.startMonitoring(.daily, during: schedule)
      resolve?(nil)
    } catch {
      reject?("0", error.localizedDescription, nil)
      print("Could not start monitoring \(error)")
    }
  }
  
  @objc
  public func getApplicationName(_ token: Any,
                                 resolver resolve: @escaping RCTPromiseResolveBlock,
                                 rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let image = ApplicationToken.toImage(token: token) else {
      return reject("0", "unable to parse token", nil)
    }
    image.detectText { resolve($0) }
  }
  
  @objc
  public func getApplicationNames(_ tokens: [Any],
                                  resolver resolve: @escaping RCTPromiseResolveBlock,
                                  rejecter reject: @escaping RCTPromiseRejectBlock) {
    var names: [[String: Any]] = []
    var iter = tokens.makeIterator()
    func extractTextFromLabel(_ token: Any?, _ retries: Int = 0) {
      if let token = token {
        ApplicationToken.toImage(token: token)?.detectText {
          usleep(IMAGE_GEN_SLEEP_INTERVAL_MICROSECONDS)
          if $0 == "" {
            if retries < 3 {
              return extractTextFromLabel(token)
            } else {
              reject("0", "unable to parse token", nil)
            }
          }
          names.append([
            "token": token as? NSDictionary ?? ["data": token as? String ?? ""],
            "name": $0,
          ])
          extractTextFromLabel(iter.next())
        }
      } else {
        resolve(names)
      }
    }
    extractTextFromLabel(iter.next())
  }
  
  @objc
  public func getCategoryName(_ token: Any,
                              resolver resolve: @escaping RCTPromiseResolveBlock,
                              rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let image = ActivityCategoryToken.toImage(token: token) else {
      return reject("0", "unable to parse token", nil)
    }
    image.detectText { resolve($0) }
  }
  
  @objc
  public func getCategoryNames(_ tokens: [Any],
                               resolver resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
    var names: [[String: Any]] = []
    var iter = tokens.makeIterator()
    func extractTextFromLabel(_ token: Any?, _ retries: Int = 0) {
      if let token = token {
        ActivityCategoryToken.toImage(token: token)?.detectText {
          usleep(IMAGE_GEN_SLEEP_INTERVAL_MICROSECONDS)
          if $0 == "" {
            if retries < 3 {
              return extractTextFromLabel(token)
            } else {
              reject("0", "unable to parse token", nil)
            }
          }
          names.append([
            "token": token as? NSDictionary ?? ["data": token as? String ?? ""],
            "name": $0,
          ])
          extractTextFromLabel(iter.next())
        }
      } else {
        resolve(names)
      }
    }
    extractTextFromLabel(iter.next())
  }
  
  @objc
  public func displayFamilyActivityPicker(_ options: NSDictionary,
                                          resolver resolve: RCTPromiseResolveBlock? = nil,
                                          rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    let activitySelection = FamilyActivitySelection.from(options["activitySelection"] as? NSDictionary)
    let title = options["title"] as? String ?? ""
    let headerText = options["headerText"] as? String ?? ""
    let footerText = options["footerText"] as? String ?? ""
    DispatchQueue.main.async {
      let view = RNTFamilyActivityPickerModalView(activitySelection: activitySelection,
                                                  title: title,
                                                  headerText: headerText,
                                                  footerText: footerText)
      {
        resolve?($0)
      }
      let vc = UIHostingController(rootView: view)
      guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else {
        reject?("0", "could not find root view controller", nil)
        return
      }
      rootViewController.present(vc, animated: true)
    }
  }
  
  // web history
  
  @objc
  public func deleteAllWebHistory(_ identifier: String? = nil,
                                  resolver resolve: RCTPromiseResolveBlock? = nil,
                                  rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    do {
      if let identifier = identifier {
        try STWebHistory(bundleIdentifier: identifier).deleteAllHistory()
      } else {
        STWebHistory().deleteAllHistory()
      }
      resolve?(nil)
    } catch {
      reject?("0", error.localizedDescription, error)
    }
  }
  
  @objc
  public func deleteWebHistoryDuring(_ interval: NSDictionary,
                                     identifier: String? = nil,
                                     resolver resolve: RCTPromiseResolveBlock? = nil,
                                     rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    guard let startDateStr = interval["startDate"] as? String,
          let startDate = DateFormatter().date(from: startDateStr),
          let durationStr = interval["duration"] as? String,
          let duration = Double(durationStr)
    else {
      reject?("0", "invalid date intrerval provided", nil)
      return
    }
    do {
      if let identifier = identifier {
        try STWebHistory(bundleIdentifier: identifier).deleteHistory(during: DateInterval(start: startDate, duration: duration / 1000))
      } else {
        STWebHistory().deleteHistory(during: DateInterval(start: startDate, duration: duration / 1000))
      }
      resolve?(nil)
    } catch {
      reject?("0", error.localizedDescription, error)
    }
  }
  
  @objc
  public func deleteWebHistoryForURL(_ url: String,
                                     identifier: String? = nil,
                                     resolver resolve: RCTPromiseResolveBlock? = nil,
                                     rejecter reject: RCTPromiseRejectBlock? = nil)
  {
    do {
      if let identifier = identifier {
        try STWebHistory(bundleIdentifier: identifier).deleteHistory(for: URL(url, strategy: .url))
      } else {
        try STWebHistory().deleteHistory(for: URL(url, strategy: .url))
      }
      resolve?(nil)
    } catch {
      reject?("0", error.localizedDescription, error)
    }
  }
}

extension DeviceActivityName {
  static let daily = Self("daily")
}
