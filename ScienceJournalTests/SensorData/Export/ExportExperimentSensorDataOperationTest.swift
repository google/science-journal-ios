/*
 *  Copyright 2019 Google Inc. All Rights Reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import XCTest

@testable import MaterialComponents
@testable import third_party_sciencejournal_ios_ScienceJournalOpen
@testable import ScienceJournalProtos

class ExportExperimentSensorDataOperationTest: XCTestCase {

  let metadataManager = MetadataManager.testingInstance
  let sensorDataManager = SensorDataManager.testStore
  let operationQueue = GSJOperationQueue()
  let testingDirectoryName = "ExportExperimentSensorDataOperationTest"
  var saveDirectoryURL: URL!

  override func setUp() {
    super.setUp()
    saveDirectoryURL =
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(testingDirectoryName)
    if FileManager.default.fileExists(atPath: saveDirectoryURL.path) {
      try! FileManager.default.removeItem(at: saveDirectoryURL)
    }

    // Clean up any old data.
    sensorDataManager.performChanges(andWait: true, save: true) {
      self.sensorDataManager.removeData(forTrialID: "METADATA_SENSOR_EXPORT_TRIAL_1")
      self.sensorDataManager.removeData(forTrialID: "METADATA_SENSOR_EXPORT_TRIAL_2")
    }
  }

  override func tearDown() {
    metadataManager.deleteRootDirectory()
    super.tearDown()
  }

  func testSensorDataProtoFromExperiment() {
    let (experiment, _) = metadataManager.createExperiment(withTitle: "Sensor Data Proto Export")
    let trial1 = Trial()
    trial1.ID = "METADATA_SENSOR_EXPORT_TRIAL_1"
    let trial2 = Trial()
    trial2.ID = "METADATA_SENSOR_EXPORT_TRIAL_2"

    let sensor1 = SensorLayout(sensorID: "Sensor_1", colorPalette: MDCPalette.blue)
    let sensor2 = SensorLayout(sensorID: "Sensor_2", colorPalette: MDCPalette.blue)
    let sensor3 = SensorLayout(sensorID: "Sensor_3", colorPalette: MDCPalette.blue)

    trial1.sensorLayouts = [sensor1]
    trial2.sensorLayouts = [sensor2, sensor3]

    experiment.trials = [trial1, trial2]
    metadataManager.saveExperiment(experiment)

    // Add data points.
    let context = sensorDataManager.privateContext
    context.performAndWait {
      trial1.sensorLayouts.forEach {
        for value in 0...9 {
          let dataPoint = DataPoint(x: Int64(value), y: Double(value))
          SensorData.insert(dataPoint: dataPoint,
                            forSensorID: $0.sensorID,
                            trialID: trial1.ID,
                            resolutionTier: 0,
                            context: context)
        }
      }
      trial2.sensorLayouts.forEach {
        for value in 0...9 {
          let dataPoint = DataPoint(x: Int64(value), y: Double(value))
          SensorData.insert(dataPoint: dataPoint,
                            forSensorID: $0.sensorID,
                            trialID: trial2.ID,
                            resolutionTier: 0,
                            context: context)
        }
      }
    }
    sensorDataManager.savePrivateContext(andWait: true)

    let expectation = XCTestExpectation()

    XCTAssertNoThrow(try FileManager.default.createDirectory(at: saveDirectoryURL,
                                                             withIntermediateDirectories: true,
                                                             attributes: nil))

    let exportSensorDataOperation =
        ExportExperimentSensorDataOperation(saveDirectoryURL: saveDirectoryURL,
                                            sensorDataManager: sensorDataManager,
                                            experiment: experiment)
    let observer = BlockObserver { (operation, errors) in
      let protoURL = self.saveDirectoryURL.appendingPathComponent("sensorData.proto")
      let data = try? Data(contentsOf: protoURL)
      XCTAssertNotNil(data)

      let sensorDataProto = try? GSJScalarSensorData(data: data!)

      XCTAssertNotNil(sensorDataProto)
      let sensors = sensorDataProto!.sensorsArray!.map { $0 as! GSJScalarSensorDataDump }
      XCTAssertEqual(3, sensors.count)
      // Sensor dumps can be in any order so fetch them by ID.
      for number in 1...3 {
        let sensorID = "Sensor_\(number)"
        let index1 = sensors.index(where: { $0.tag == sensorID })!
        let sensorProto1 = sensors[index1]
        XCTAssertEqual(10, sensorProto1.rowsArray.count)
        if number == 1 {
          XCTAssertEqual(trial1.ID, sensorProto1.trialId)
        } else if number == 2 || number == 3 {
          XCTAssertEqual(trial2.ID, sensorProto1.trialId)
        }
      }
      expectation.fulfill()
    }
    exportSensorDataOperation.addObserver(observer)
    operationQueue.addOperation(exportSensorDataOperation)

    wait(for: [expectation], timeout: 10)
  }

}
