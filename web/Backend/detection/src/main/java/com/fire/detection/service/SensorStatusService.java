package com.fire.detection.service;


public interface SensorStatusService  {
    void updateLastSeen(String deviceId, String sensorId, double temperature, String location, String status);

}
