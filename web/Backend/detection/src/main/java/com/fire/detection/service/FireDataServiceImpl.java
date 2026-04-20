package com.fire.detection.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fire.detection.DTO.Esp32Payload;
import com.fire.detection.model.EStatus;
import com.fire.detection.model.FireData;
import com.fire.detection.model.SensorStatus;
import com.fire.detection.repository.FireDataRepository;
import com.fire.detection.repository.SensorStatusRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class FireDataServiceImpl implements FireDataService{
    private final FireDataRepository fireDataRepository;
    private final SensorStatusRepository sensorStatusRepository;
    private final SensorStatusService sensorStatusService;
    @Override
    public void saveFireData(FireData fireData) {

        // 1. Lưu history
        fireDataRepository.save(fireData);

        // 2. Update trạng thái hiện tại
        String id = fireData.getDeviceId() + "_" + fireData.getSensorId();

        SensorStatus status = SensorStatus.builder()
                .id(id)
                .deviceId(fireData.getDeviceId())
                .sensorId(fireData.getSensorId())
                .temperature(fireData.getTemperature())
                .status(fireData.getStatus())
                .location(fireData.getLocation())
                .deviceStatus(fireData.getDeviceStatus())
                .lastUpdated(LocalDateTime.now())
                .build();

        sensorStatusRepository.save(status); // overwrite = latest
    }

    @Override
    public List<SensorStatus> getAllStatus() {
        return sensorStatusRepository.findAll();
    }

    @Override
    public void process(String payload) {
        ObjectMapper mapper = new ObjectMapper();

        try {
            Esp32Payload dto = mapper.readValue(payload, Esp32Payload.class);

            FireData data = FireData.builder()
                    .deviceId(dto.getNode_id())
                    .sensorId("S1") // 🔥 fix cứng hoặc mapping sau
                    .location("ROOM_1") // 🔥 fix cứng hoặc config
                    .temperature(dto.getTemperature())
                    .status(dto.getFire_status().equals("FIRE") ? EStatus.FIRE : EStatus.NORMAL)
                    .deviceStatus(dto.getDevice_status())
                    .build();

            saveFireData(data);

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    @Override
    @Transactional
    public void clearAllData() {
        // Xóa lịch sử dữ liệu cảm biến
        fireDataRepository.deleteAll();

        // Xóa trạng thái hiện tại của các sensor
        sensorStatusRepository.deleteAll();

        System.out.println("Database has been cleared at " + LocalDateTime.now());
    }

    @Override
    public List<FireData> getHistory(String deviceId) {
        return fireDataRepository.findByDeviceIdOrderByCreatedAtAsc(deviceId);
    }
    public List<FireData> getHistoryByTime(String deviceId, long seconds) {
        LocalDateTime from = LocalDateTime.now().minusSeconds(seconds);
        return fireDataRepository.findByDeviceIdAndCreatedAtAfterOrderByCreatedAtAsc(deviceId, from);
    }
}
