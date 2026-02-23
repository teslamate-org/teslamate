import SwiftUI
import Charts

struct ChargeCurveChart: View {
    let charges: [ChargeDataPoint]

    private var chartData: [(index: Int, power: Int, soc: Int)] {
        charges.enumerated().compactMap { index, charge in
            guard let power = charge.chargerPower, let soc = charge.batteryLevel else {
                return nil
            }
            return (index: index, power: power, soc: soc)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge Curve")
                .font(.headline)

            Chart {
                ForEach(chartData, id: \.index) { point in
                    LineMark(
                        x: .value("SOC", point.soc),
                        y: .value("Power (kW)", point.power)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("SOC", point.soc),
                        y: .value("Power (kW)", point.power)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxisLabel("Battery %")
            .chartYAxisLabel("Power (kW)")
        }
    }
}
