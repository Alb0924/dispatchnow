package com.dispatchnow.app;

import com.dispatchnow.account.AccountModule;
import com.dispatchnow.fulfillment.FulfillmentModule;
import com.dispatchnow.payment.PaymentModule;
import com.dispatchnow.pricing.PricingModule;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * DispatchNow 唯一启动入口。
 * 各模块通过普通 Java 依赖装配到同一个进程中。
 */
@SpringBootApplication(scanBasePackageClasses = {
        DispatchNowApplication.class,
        AccountModule.class,
        FulfillmentModule.class,
        PricingModule.class,
        PaymentModule.class
})
public class DispatchNowApplication {

    public static void main(String[] args) {
        SpringApplication.run(DispatchNowApplication.class, args);
    }
}
