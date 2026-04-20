package com.fire.detection.repository;

import com.fire.detection.model.SensorStatus;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SensorStatusRepository extends JpaRepository<SensorStatus, String> {
}
