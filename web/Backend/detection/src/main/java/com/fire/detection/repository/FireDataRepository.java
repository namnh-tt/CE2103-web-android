package com.fire.detection.repository;

import com.fire.detection.model.FireData;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface FireDataRepository extends JpaRepository<FireData,Long> {
    List<FireData> findByDeviceId(String deviceId);
    List<FireData> findBySensorId(String sensorId);
    List<FireData> findByCreatedAtAfter(LocalDateTime time);
    List<FireData> findByDeviceIdOrderByCreatedAtAsc(String deviceId);

    List<FireData> findByDeviceIdAndCreatedAtAfterOrderByCreatedAtAsc(
            String deviceId, LocalDateTime time
    );
}
