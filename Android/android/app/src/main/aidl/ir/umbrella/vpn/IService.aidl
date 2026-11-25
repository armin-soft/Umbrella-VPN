package ir.umbrella.vpn;

import ir.umbrella.vpn.IServiceCallback;

interface IService {
    int getStatus();
    void registerCallback(in IServiceCallback callback);
    oneway void unregisterCallback(in IServiceCallback callback);
}
