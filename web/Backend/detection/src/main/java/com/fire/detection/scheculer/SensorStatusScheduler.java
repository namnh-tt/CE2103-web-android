package com.fire.detection.scheculer;

import com.fire.detection.model.EStatus;
import com.fire.detection.model.SensorStatus;
import com.fire.detection.repository.SensorStatusRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;

@Component
@RequiredArgsConstructor
public class SensorStatusScheduler {
    private final SensorStatusRepository sensorStatusRepository;

    @Scheduled(fixedRate = 5000) // mỗi 5 giây chạy 1 lần
    public void checkOfflineSensors() {

        List<SensorStatus> list = sensorStatusRepository.findAll();
        LocalDateTime now = LocalDateTime.now();

        for (SensorStatus s : list) {
            if (s.getLastUpdated().isBefore(now.minusSeconds(30))) {
                s.setStatus(EStatus.OFFLINE);
                sensorStatusRepository.save(s);
            }
        }
    }
}
