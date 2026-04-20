package com.fire.detection.service;

import com.fire.detection.model.FireData;
import com.fire.detection.model.SensorStatus;

import java.util.List;

public interface FireDataService {
    void saveFireData(FireData fireData);

    List<SensorStatus> getAllStatus();
    void process(String payload);
    void clearAllData();
    List<FireData> getHistory(String deviceId);
    List<FireData> getHistoryByTime(String deviceId, long seconds);

}
