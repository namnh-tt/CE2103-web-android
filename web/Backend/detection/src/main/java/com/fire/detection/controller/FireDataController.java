package com.fire.detection.controller;

import com.fire.detection.model.FireData;
import com.fire.detection.model.SensorStatus;
import com.fire.detection.service.FireDataService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/fire-data")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class FireDataController {

    private final FireDataService fireDataService;

    @PostMapping
    public String receiveData(@RequestBody FireData fireData) {
        fireDataService.saveFireData(fireData);
        return "OK";
    }

    // Frontend gọi API này
    @GetMapping("/status")
    public List<SensorStatus> getStatus() {
        return fireDataService.getAllStatus();
    }

    // API để xóa sạch dữ liệu
    @DeleteMapping("/clear")
    public String clearAllData() {
        fireDataService.clearAllData();
        return "Đã dọn dẹp sạch toàn bộ dữ liệu database!";
    }

    @GetMapping("/history/{deviceId}")
    public List<FireData> getHistory(@PathVariable String deviceId) {
        return fireDataService.getHistory(deviceId);
    }

    @GetMapping("/history/{deviceId}/{seconds}")
    public List<FireData> getHistoryByTime(
            @PathVariable String deviceId,
            @PathVariable long seconds) {
        return fireDataService.getHistoryByTime(deviceId, seconds);
    }
}