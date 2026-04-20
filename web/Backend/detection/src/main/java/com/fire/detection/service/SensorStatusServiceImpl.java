package com.fire.detection.service;

import com.fire.detection.model.EStatus;
import com.fire.detection.model.SensorStatus;
import com.fire.detection.repository.SensorStatusRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class SensorStatusServiceImpl implements SensorStatusService {
    private final SensorStatusRepository sensorStatusRepository;

    @Override
    public void updateLastSeen(String deviceId, String sensorId,
                               double temperature, String location, String statusStr) {

        String id = deviceId + "_" + sensorId;

        EStatus status = EStatus.valueOf(statusStr); // convert String → Enum

        SensorStatus sensorStatus = SensorStatus.builder()
                .id(id)
                .deviceId(deviceId)
                .sensorId(sensorId)
                .temperature(temperature)
                .location(location)
                .status(status)
                .lastUpdated(LocalDateTime.now())
                .build();

        sensorStatusRepository.save(sensorStatus); // overwrite = latest
    }
}
