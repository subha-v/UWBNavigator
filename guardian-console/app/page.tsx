"use client"

import { useState, useEffect } from "react"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { TrendingUp, TrendingDown, Clock, CheckCircle, XCircle, Loader } from "lucide-react"
import { useAnchors, useNavigators, useLatestSession, calculateQoDFromMeasurements } from "@/hooks/useFirebaseData"

interface Anchor {
  id: string
  floor: string
  qod: number
  residualP95: number
  jitterP95: number
  uwbHz: number
  dropouts: number
  geometryScore: number
  status: "healthy" | "warning" | "poor" | "quarantined"
  lastCalibration: string
  firmware: string
  coords: { x: number; y: number; z: number }
  battery: number
}

interface Robot {
  id: string
  intent: string
  destination: string
  routeEta: number
  currentFloor: string
  positionConfidence: number
  anchorsUsed: number
  anchorsExcluded: number
  guardianState: "Normal" | "Degraded" | "Failsafe"
  status: "active" | "idle" | "error"
  lastPosition: { x: number; y: number }
  batteryLevel: number
  qodScore: number
  photoSimilarity: number
}

interface SmartContract {
  txId: string
  robotId: string
  anchors: string[]
  asset: string
  price: number
  currency: "credits" | "USDC"
  status: "Pending" | "Executing" | "Settled" | "Failed"
  qodQuorum: "Pass" | "Fail"
  timestamp: Date
  dop: number
  minAnchors: number
  actualAnchors: number
  navigatorId: string
}

function getQoDBadge(qod: number) {
  if (qod >= 80)
    return <Badge className="bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">{qod}%</Badge>
  if (qod >= 50)
    return <Badge className="bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200">{qod}%</Badge>
  return <Badge className="bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">{qod}%</Badge>
}

function getContractStatusBadge(status: string) {
  switch (status) {
    case "Pending":
      return (
        <Badge className="bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
          <Loader className="w-3 h-3 mr-1" />
          Pending
        </Badge>
      )
    case "Executing":
      return (
        <Badge className="bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200">
          <Clock className="w-3 h-3 mr-1" />
          Executing
        </Badge>
      )
    case "Settled":
      return (
        <Badge className="bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
          <CheckCircle className="w-3 h-3 mr-1" />
          Settled
        </Badge>
      )
    case "Failed":
      return (
        <Badge className="bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
          <XCircle className="w-3 h-3 mr-1" />
          Failed
        </Badge>
      )
    default:
      return <Badge variant="outline">{status}</Badge>
  }
}

function getQuorumBadge(quorum: string) {
  if (quorum === "Pass")
    return <Badge className="bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">Pass</Badge>
  return <Badge className="bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">Fail</Badge>
}

function formatTimeAgo(date: Date) {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  return `${hours}h ago`
}

export default function GuardianConsole() {
  const [environment, setEnvironment] = useState("Production")
  const [lastUpdated, setLastUpdated] = useState(new Date())
  
  // Use Firebase hooks
  const { anchors: firebaseAnchors, loading: anchorsLoading } = useAnchors()
  const { navigators: firebaseNavigators, loading: navigatorsLoading } = useNavigators()
  const { measurements, loading: measurementsLoading } = useLatestSession()
  
  // Calculate QoD from measurements
  const globalQoD = calculateQoDFromMeasurements(measurements)
  
  // Transform Firebase data to match component interface
  const anchors: Anchor[] = firebaseAnchors.map(anchor => ({
    id: anchor.agentId,
    floor: "Floor 2",
    qod: anchor.qodScore || globalQoD || 0,
    battery: anchor.battery,
    status: anchor.status === 'online' 
      ? (anchor.qodScore && anchor.qodScore > 80 ? "healthy" 
        : anchor.qodScore && anchor.qodScore > 50 ? "warning" 
        : "poor") 
      : "quarantined" as any,
    residualP95: 0.15,
    jitterP95: 2.3,
    uwbHz: 120,
    dropouts: 0.8,
    geometryScore: 8.7,
    lastCalibration: "2024-01-15",
    firmware: "v2.1.3",
    coords: { x: 12.5, y: 8.2, z: 3.1 },
  }))

  // Transform navigators to robots
  const robots: Robot[] = firebaseNavigators.map(nav => ({
    id: nav.agentId,
    intent: "Navigation Active",
    destination: "Tracking",
    routeEta: 0,
    currentFloor: "Floor 2",
    positionConfidence: 0.94,
    anchorsUsed: firebaseAnchors.filter(a => a.status === 'online').length,
    anchorsExcluded: 0,
    guardianState: nav.status === 'online' ? "Normal" as const : "Degraded" as const,
    status: nav.status === 'online' ? "active" as const : "idle" as const,
    lastPosition: { x: 8.3, y: 12.1 },
    batteryLevel: nav.battery,
    qodScore: nav.qodScore || globalQoD || 0,
    photoSimilarity: 94
  }))

  // Generate contracts based on measurements
  const contracts: SmartContract[] = measurements.slice(0, 5).map((m, i) => ({
    txId: `0x${m.timestamp.getTime().toString(16).substr(-8)}`,
    navigatorId: firebaseNavigators[0]?.agentId || "Navigator",
    anchors: firebaseAnchors.map(a => a.agentId).slice(0, 3),
    asset: "Distance measurement",
    price: 12,
    currency: "USDC" as const,
    status: i === 0 ? "Executing" as const : "Settled" as const,
    qodQuorum: Math.abs(m.k) < 0.2 ? "Pass" as const : "Fail" as const,
    timestamp: m.timestamp,
    dop: Math.abs(m.e),
    minAnchors: 3,
    actualAnchors: firebaseAnchors.filter(a => a.status === 'online').length,
    robotId: firebaseNavigators[0]?.agentId || "Navigator"
  }))

  const [anchorSearch, setAnchorSearch] = useState("")
  const [robotSearch, setRobotSearch] = useState("")
  const [contractSearch, setContractSearch] = useState("")
  const [selectedContract, setSelectedContract] = useState<SmartContract | null>(null)

  const filteredAnchors = anchors.filter((anchor) => {
    return anchor.id.toLowerCase().includes(anchorSearch.toLowerCase())
  })

  const filteredRobots = robots.filter((robot) => {
    return robot.id.toLowerCase().includes(robotSearch.toLowerCase())
  })

  const filteredContracts = contracts.filter((contract) => {
    return contract.txId.toLowerCase().includes(contractSearch.toLowerCase()) ||
           contract.navigatorId.toLowerCase().includes(contractSearch.toLowerCase())
  })

  // Update last updated time
  useEffect(() => {
    const interval = setInterval(() => {
      setLastUpdated(new Date())
    }, 5000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="min-h-screen bg-background">
      <header className="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="flex h-14 items-center px-4">
          <div className="flex items-center space-x-4">
            <h1 className="text-xl font-semibold">Guardian Console</h1>
            <Select defaultValue="production">
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="production">Production</SelectItem>
                <SelectItem value="staging">Staging</SelectItem>
                <SelectItem value="development">Development</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="ml-auto flex items-center space-x-4">
            <div className="flex items-center space-x-2 text-sm text-muted-foreground">
              <div className="flex items-center space-x-1">
                <div className="h-2 w-2 rounded-full bg-green-500"></div>
                <span>Live</span>
              </div>
              <span>•</span>
              <span>Updated {formatTimeAgo(lastUpdated)}</span>
            </div>
          </div>
        </div>
      </header>

      {/* Three Panel Layout */}
      <div className="flex h-[calc(100vh-120px)] gap-4 p-6">
        {/* Left Panel - Anchors */}
        <div className="flex-1 border-r">
          <div className="border-b p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">Anchors</h2>
              <Input
                placeholder="Search anchors..."
                value={anchorSearch}
                onChange={(e) => setAnchorSearch(e.target.value)}
                className="w-40"
              />
            </div>
          </div>

          <div className="p-4">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-20">Agent ID</TableHead>
                  <TableHead className="w-20">QoD Score</TableHead>
                  <TableHead className="w-20">Battery</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {anchorsLoading ? (
                  <TableRow>
                    <TableCell colSpan={3} className="text-center">
                      <Loader className="w-4 h-4 inline animate-spin mr-2" />
                      Loading anchors...
                    </TableCell>
                  </TableRow>
                ) : filteredAnchors.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={3} className="text-center text-muted-foreground">
                      No anchors online
                    </TableCell>
                  </TableRow>
                ) : filteredAnchors.map((anchor) => (
                  <TableRow key={anchor.id}>
                    <TableCell className="font-mono">{anchor.id}</TableCell>
                    <TableCell>
                      {anchor.qod ? getQoDBadge(anchor.qod) : <Badge variant="outline">N/A</Badge>}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center space-x-1">
                        <span className="text-sm">{anchor.battery}%</span>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>

        {/* Middle Panel - Navigators */}
        <div className="flex-[1.33] border-r">
          <div className="border-b p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">Navigators</h2>
              <Input
                placeholder="Search navigators..."
                value={robotSearch}
                onChange={(e) => setRobotSearch(e.target.value)}
                className="w-40"
              />
            </div>
          </div>

          <div className="p-4">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-20">Agent ID</TableHead>
                  <TableHead className="w-20">QoD Score</TableHead>
                  <TableHead className="w-20">Battery</TableHead>
                  <TableHead className="w-20">Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {navigatorsLoading ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center">
                      <Loader className="w-4 h-4 inline animate-spin mr-2" />
                      Loading navigators...
                    </TableCell>
                  </TableRow>
                ) : filteredRobots.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center text-muted-foreground">
                      No navigators online
                    </TableCell>
                  </TableRow>
                ) : filteredRobots.map((robot) => (
                  <TableRow key={robot.id}>
                    <TableCell className="font-mono">{robot.id}</TableCell>
                    <TableCell>
                      {robot.qodScore ? getQoDBadge(robot.qodScore) : <Badge variant="outline">N/A</Badge>}
                    </TableCell>
                    <TableCell>
                      <span className="text-sm">{robot.batteryLevel}%</span>
                    </TableCell>
                    <TableCell>
                      <Badge variant={robot.status === "active" ? "default" : "secondary"}>
                        {robot.status}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>

        {/* Right Panel - Smart Contracts */}
        <div className="flex-1">
          <div className="border-b p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">Smart Contracts</h2>
              <Input
                placeholder="Search contracts..."
                value={contractSearch}
                onChange={(e) => setContractSearch(e.target.value)}
                className="w-40"
              />
            </div>
          </div>

          <div className="p-4">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-20">Tx ID</TableHead>
                  <TableHead className="w-20">Navigator</TableHead>
                  <TableHead className="w-16">Error</TableHead>
                  <TableHead className="w-20">Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {measurementsLoading || contracts.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center text-muted-foreground">
                      No active measurements
                    </TableCell>
                  </TableRow>
                ) : filteredContracts.map((contract) => (
                  <TableRow
                    key={contract.txId}
                    className="cursor-pointer"
                    onClick={() => setSelectedContract(contract)}
                  >
                    <TableCell className="font-mono text-xs">{contract.txId.slice(0, 10)}...</TableCell>
                    <TableCell className="font-mono">{contract.navigatorId}</TableCell>
                    <TableCell>{contract.dop.toFixed(2)}m</TableCell>
                    <TableCell>{getQuorumBadge(contract.qodQuorum)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>
      </div>

      {/* Contract detail drawer */}
      <Sheet open={!!selectedContract} onOpenChange={() => setSelectedContract(null)}>
        <SheetContent className="w-[400px] sm:w-[540px]">
          <SheetHeader>
            <SheetTitle>Measurement {selectedContract?.txId}</SheetTitle>
            <SheetDescription>
              {selectedContract?.navigatorId} • {formatTimeAgo(selectedContract?.timestamp || new Date())}
            </SheetDescription>
          </SheetHeader>

          {selectedContract && (
            <div className="mt-6 space-y-6">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-sm font-medium">Status</div>
                  <div className="mt-1">{getContractStatusBadge(selectedContract.status)}</div>
                </div>
                <div>
                  <div className="text-sm font-medium">QoD Result</div>
                  <div className="mt-1">{getQuorumBadge(selectedContract.qodQuorum)}</div>
                </div>
              </div>

              <div className="space-y-3">
                <h4 className="font-medium">Measurement Details</h4>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Error (meters)</span>
                    <span className="font-medium">{selectedContract.dop.toFixed(3)}m</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Anchors Available</span>
                    <span>{selectedContract.actualAnchors} of {selectedContract.minAnchors}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Timestamp</span>
                    <span className="font-mono text-xs">{selectedContract.timestamp.toISOString()}</span>
                  </div>
                </div>
              </div>

              <div className="space-y-3">
                <h4 className="font-medium">Participating Anchors</h4>
                <div className="space-y-2">
                  {selectedContract.anchors.map((anchorId) => (
                    <div key={anchorId} className="flex items-center justify-between text-sm">
                      <span className="font-mono">{anchorId}</span>
                      <Badge variant="outline" className="text-xs">Connected</Badge>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </SheetContent>
      </Sheet>
    </div>
  )
}