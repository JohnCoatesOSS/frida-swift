import Foundation

@dynamicCallable
public struct RpcFunction {
    unowned let script: Script
    let functionName: String

    init(script: Script, functionName: String) {
        self.script = script
        self.functionName = functionName
    }

    func dynamicallyCall(withArguments args: [Any]) -> RpcRequest {
        return script.rpcPost(functionName: functionName,
                              requestId: script.nextRequestId, values: args)
    }
}

@dynamicCallable
public struct RpcFunctionSync<Result> {
    unowned let script: Script
    let functionName: String

    init(script: Script, functionName: String) {
        self.script = script
        self.functionName = functionName
    }

    func dynamicallyCall(withArguments args: [Any]) throws -> Result {
        let untypedValue = try script.rpcPostSync(functionName: functionName,
                                                  requestId: script.nextRequestId, values: args)

        guard let value = untypedValue as? Result else {
            throw Error.rpcError(message: "Couldn't cast value \(String(describing: untypedValue)) to \(Result.self).", stackTrace: nil)
        }
        return value
    }
}
