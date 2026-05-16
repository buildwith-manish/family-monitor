'use client';

import React, { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient, QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import {
  LayoutDashboard, Users, Smartphone, Clock, BarChart3, MapPin,
  Shield, Bell, Calendar, Menu, Moon, Sun, ChevronDown, ChevronRight,
  Plus, Battery, Wifi, WifiOff, Eye, EyeOff, AlertTriangle,
  AlertCircle, CheckCircle, MapPinned, Monitor, Tablet, Laptop,
  ShieldAlert, Gamepad2, GraduationCap, Film, Briefcase, MessageCircle,
  ChevronUp
} from 'lucide-react';
import { useTheme } from 'next-themes';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Switch } from '@/components/ui/switch';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Progress } from '@/components/ui/progress';
import { Separator } from '@/components/ui/separator';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend
} from 'recharts';

// Types
interface FamilyData {
  id: string;
  name: string;
  code: string;
  members: MemberData[];
}

interface MemberData {
  id: string;
  name: string;
  email: string | null;
  role: string;
  avatar: string | null;
  familyId: string;
  devices: DeviceData[];
}

interface DeviceData {
  id: string;
  name: string;
  type: string;
  os: string | null;
  model: string | null;
  status: string;
  batteryLevel: number | null;
  lastSeen: string | null;
  memberId: string;
  member?: MemberData;
  screenTime: ScreenTimeData[];
  appUsage: AppUsageData[];
  location: LocationData[];
}

interface ScreenTimeData {
  id: string;
  date: string;
  totalMinutes: number;
  limitMinutes: number | null;
  deviceId: string;
  device?: { name: string; member?: { name: string } };
}

interface AppUsageData {
  id: string;
  appName: string;
  category: string | null;
  usageMinutes: number;
  date: string;
  deviceId: string;
  device?: { name: string; member?: { name: string } };
}

interface LocationData {
  id: string;
  latitude: number;
  longitude: number;
  address: string | null;
  timestamp: string;
  deviceId: string;
  device?: { name: string; member?: { name: string } };
}

interface AlertData {
  id: string;
  type: string;
  severity: string;
  title: string;
  message: string;
  read: boolean;
  memberId: string | null;
  deviceId: string | null;
  createdAt: string;
  member?: { name: string; avatar: string | null } | null;
  device?: { name: string } | null;
}

interface ContentFilterData {
  id: string;
  category: string;
  enabled: boolean;
  blockLevel: string;
  deviceId: string | null;
  device?: { name: string; member?: { name: string } } | null;
}

interface ScheduleData {
  id: string;
  name: string;
  type: string;
  startHour: number;
  startMinute: number;
  endHour: number;
  endMinute: number;
  daysOfWeek: string;
  allowApps: string;
  deviceId: string | null;
  enabled: boolean;
  device?: { name: string; member?: { name: string } } | null;
}

type Section = 'dashboard' | 'family' | 'devices' | 'screentime' | 'appusage' | 'location' | 'filters' | 'alerts' | 'schedules';

const SECTIONS: { id: Section; label: string; icon: React.ElementType }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'family', label: 'Family', icon: Users },
  { id: 'devices', label: 'Devices', icon: Smartphone },
  { id: 'screentime', label: 'Screen Time', icon: Clock },
  { id: 'appusage', label: 'App Usage', icon: BarChart3 },
  { id: 'location', label: 'Location', icon: MapPin },
  { id: 'filters', label: 'Filters', icon: Shield },
  { id: 'alerts', label: 'Alerts', icon: Bell },
  { id: 'schedules', label: 'Schedules', icon: Calendar },
];

const CHART_COLORS = ['#10b981', '#34d399', '#6ee7b7', '#a7f3d0', '#d1fae5', '#059669', '#047857'];
const CATEGORY_COLORS: Record<string, string> = {
  social: '#f59e0b',
  games: '#ef4444',
  education: '#10b981',
  entertainment: '#8b5cf6',
  productivity: '#3b82f6',
};

const SEVERITY_COLORS: Record<string, string> = {
  info: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
  warning: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
  critical: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
};

const DAY_NAMES = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function formatMinutes(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function formatDateTime(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function formatTime(hour: number, minute: number): string {
  const period = hour >= 12 ? 'PM' : 'AM';
  const h = hour > 12 ? hour - 12 : hour === 0 ? 12 : hour;
  return `${h}:${minute.toString().padStart(2, '0')} ${period}`;
}

function getDeviceIcon(type: string) {
  switch (type) {
    case 'smartphone': return Smartphone;
    case 'tablet': return Tablet;
    case 'laptop': return Laptop;
    case 'desktop': return Monitor;
    default: return Smartphone;
  }
}

function getCategoryIcon(category: string) {
  switch (category) {
    case 'social': return MessageCircle;
    case 'games': return Gamepad2;
    case 'education': return GraduationCap;
    case 'entertainment': return Film;
    case 'productivity': return Briefcase;
    default: return BarChart3;
  }
}

function getAlertIcon(type: string) {
  switch (type) {
    case 'geofence': return MapPinned;
    case 'screen_time': return Clock;
    case 'app_install': return Plus;
    case 'content_access': return ShieldAlert;
    case 'sos': return AlertTriangle;
    default: return Bell;
  }
}

// Create a stable QueryClient instance
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30 * 1000,
      refetchOnWindowFocus: false,
    },
  },
});

export default function FamilyMonitorPage() {
  return (
    <QueryClientProvider client={queryClient}>
      <FamilyMonitorContent />
    </QueryClientProvider>
  );
}

function FamilyMonitorContent() {
  const [activeSection, setActiveSection] = useState<Section>('dashboard');
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState<string | null>(null);
  const [expandedMember, setExpandedMember] = useState<string | null>(null);
  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [addScheduleOpen, setAddScheduleOpen] = useState(false);
  const [alertFilter, setAlertFilter] = useState<string>('all');
  const [filterDevice, setFilterDevice] = useState<string>('all');
  const [newMember, setNewMember] = useState({ name: '', email: '', role: 'child', avatar: '🧑' });
  const [newSchedule, setNewSchedule] = useState({
    name: '', type: 'bedtime', startHour: 21, startMinute: 0,
    endHour: 7, endMinute: 0, daysOfWeek: '1,2,3,4,5,6,7', allowApps: '', deviceId: ''
  });
  const { theme, setTheme } = useTheme();
  const queryClient = useQueryClient();

  // Fetch family data
  const { data: family, isLoading: familyLoading } = useQuery<FamilyData>({
    queryKey: ['family'],
    queryFn: () => fetch('/api/family').then(r => r.json()),
  });

  // Fetch devices
  const { data: devices } = useQuery<DeviceData[]>({
    queryKey: ['devices'],
    queryFn: () => fetch('/api/devices').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch screen time
  const { data: screenTimeData } = useQuery<ScreenTimeData[]>({
    queryKey: ['screentime'],
    queryFn: () => fetch('/api/screentime').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch app usage
  const { data: appUsageData } = useQuery<AppUsageData[]>({
    queryKey: ['appusage'],
    queryFn: () => fetch('/api/app-usage').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch locations
  const { data: locationData } = useQuery<LocationData[]>({
    queryKey: ['locations'],
    queryFn: () => fetch('/api/locations').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch alerts
  const { data: alertData } = useQuery<AlertData[]>({
    queryKey: ['alerts'],
    queryFn: () => fetch('/api/alerts').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch filters
  const { data: filterData } = useQuery<ContentFilterData[]>({
    queryKey: ['filters'],
    queryFn: () => fetch('/api/filters').then(r => r.json()),
    enabled: !!family,
  });

  // Fetch schedules
  const { data: scheduleData } = useQuery<ScheduleData[]>({
    queryKey: ['schedules'],
    queryFn: () => fetch('/api/schedules').then(r => r.json()),
    enabled: !!family,
  });

  // Seed on first load
  const seedMutation = useMutation({
    mutationFn: () => fetch('/api/seed').then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['family'] });
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['screentime'] });
      queryClient.invalidateQueries({ queryKey: ['appusage'] });
      queryClient.invalidateQueries({ queryKey: ['locations'] });
      queryClient.invalidateQueries({ queryKey: ['alerts'] });
      queryClient.invalidateQueries({ queryKey: ['filters'] });
      queryClient.invalidateQueries({ queryKey: ['schedules'] });
    },
  });

  // Add member mutation
  const addMemberMutation = useMutation({
    mutationFn: (data: typeof newMember) =>
      fetch('/api/family', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...data, familyId: family?.id }),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['family'] });
      setAddMemberOpen(false);
      setNewMember({ name: '', email: '', role: 'child', avatar: '🧑' });
    },
  });

  // Update device mutation
  const updateDeviceMutation = useMutation({
    mutationFn: ({ id, ...data }: { id: string; status?: string; batteryLevel?: number }) =>
      fetch(`/api/devices/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['family'] });
    },
  });

  // Mark alert as read mutation
  const markAlertMutation = useMutation({
    mutationFn: (id: string) =>
      fetch(`/api/alerts/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ read: true }),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alerts'] });
    },
  });

  // Update filter mutation
  const updateFilterMutation = useMutation({
    mutationFn: (data: { id: string; enabled?: boolean; blockLevel?: string }) =>
      fetch('/api/filters', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['filters'] });
    },
  });

  // Set screen time limit mutation
  const setScreenTimeLimitMutation = useMutation({
    mutationFn: (data: { deviceId: string; limitMinutes: number }) =>
      fetch('/api/screentime', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['screentime'] });
      queryClient.invalidateQueries({ queryKey: ['devices'] });
    },
  });

  // Add schedule mutation
  const addScheduleMutation = useMutation({
    mutationFn: (data: typeof newSchedule) =>
      fetch('/api/schedules', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['schedules'] });
      setAddScheduleOpen(false);
      setNewSchedule({
        name: '', type: 'bedtime', startHour: 21, startMinute: 0,
        endHour: 7, endMinute: 0, daysOfWeek: '1,2,3,4,5,6,7', allowApps: '', deviceId: ''
      });
    },
  });

  // Toggle schedule mutation
  const toggleScheduleMutation = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      fetch(`/api/schedules/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enabled }),
      }).then(r => r.json()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['schedules'] });
    },
  });

  // Auto-seed on first load
  useEffect(() => {
    if (!family && !familyLoading) {
      seedMutation.mutate();
    }
  }, [family, familyLoading]);

  // Compute dashboard stats
  const allDevices = devices || [];
  const onlineDevices = allDevices.filter(d => d.status === 'online');
  const offlineDevices = allDevices.filter(d => d.status === 'offline');
  const allAlerts = alertData || [];
  const unreadAlerts = allAlerts.filter(a => !a.read);
  const allMembers = family?.members || [];
  const childMembers = allMembers.filter(m => m.role === 'child');

  // Today's screen time
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const todayScreenTime = (screenTimeData || []).filter(st => {
    const stDate = new Date(st.date);
    stDate.setHours(0, 0, 0, 0);
    return stDate.getTime() === today.getTime();
  });

  const totalScreenTimeToday = todayScreenTime.reduce((sum, st) => sum + st.totalMinutes, 0);

  // Most used app today
  const todayAppUsage = (appUsageData || []).filter(au => {
    const auDate = new Date(au.date);
    auDate.setHours(0, 0, 0, 0);
    return auDate.getTime() === today.getTime();
  });

  const appUsageMap = new Map<string, number>();
  todayAppUsage.forEach(au => {
    appUsageMap.set(au.appName, (appUsageMap.get(au.appName) || 0) + au.usageMinutes);
  });
  const mostUsedApp = Array.from(appUsageMap.entries()).sort((a, b) => b[1] - a[1])[0];

  // Average battery
  const batteries = allDevices.filter(d => d.batteryLevel !== null).map(d => d.batteryLevel!);
  const avgBattery = batteries.length ? Math.round(batteries.reduce((a, b) => a + b, 0) / batteries.length) : 0;

  // Weekly screen time chart data
  const weeklyScreenTimeData = (() => {
    const days: { day: string; total: number; limit: number }[] = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      d.setHours(0, 0, 0, 0);
      const dayName = d.toLocaleDateString('en-US', { weekday: 'short' });
      const dayData = (screenTimeData || []).filter(st => {
        const stDate = new Date(st.date);
        stDate.setHours(0, 0, 0, 0);
        return stDate.getTime() === d.getTime();
      });
      const total = dayData.reduce((sum, st) => sum + st.totalMinutes, 0);
      const avgLimit = dayData.filter(st => st.limitMinutes).length
        ? Math.round(dayData.filter(st => st.limitMinutes).reduce((sum, st) => sum + (st.limitMinutes || 0), 0) / dayData.filter(st => st.limitMinutes).length)
        : 0;
      days.push({ day: dayName, total: Math.round(total / Math.max(dayData.length, 1)), limit: avgLimit });
    }
    return days;
  })();

  // Top apps for pie chart
  const topAppsData = (() => {
    const appTotals = new Map<string, { total: number; category: string }>();
    (appUsageData || []).forEach(au => {
      const existing = appTotals.get(au.appName);
      if (existing) {
        existing.total += au.usageMinutes;
      } else {
        appTotals.set(au.appName, { total: au.usageMinutes, category: au.category || 'other' });
      }
    });
    return Array.from(appTotals.entries())
      .map(([name, data]) => ({ name, value: data.total, category: data.category }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 8);
  })();

  // App category breakdown
  const categoryBreakdown = (() => {
    const cats = new Map<string, number>();
    (appUsageData || []).forEach(au => {
      const cat = au.category || 'other';
      cats.set(cat, (cats.get(cat) || 0) + au.usageMinutes);
    });
    return Array.from(cats.entries())
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value);
  })();

  // Geofence alerts
  const geofenceAlerts = allAlerts.filter(a => a.type === 'geofence');

  // Filter alerts
  const filteredAlerts = allAlerts.filter(a => {
    if (alertFilter !== 'all' && a.severity !== alertFilter) return false;
    return true;
  });

  // Filter content filters by device
  const filteredContentFilters = (filterData || []).filter(f => {
    if (filterDevice !== 'all' && f.deviceId !== filterDevice) return false;
    return true;
  });

  // Sidebar content
  const SidebarContent = () => (
    <div className="flex flex-col h-full">
      <div className="p-4 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
            <Shield className="w-5 h-5 text-primary-foreground" />
          </div>
          <div>
            <h2 className="font-bold text-sm">Family Monitor</h2>
            <p className="text-xs text-muted-foreground">Parental Control</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 p-2 space-y-1">
        {SECTIONS.map(section => {
          const Icon = section.icon;
          const isActive = activeSection === section.id;
          return (
            <button
              key={section.id}
              onClick={() => { setActiveSection(section.id); setSidebarOpen(false); }}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 ${
                isActive
                  ? 'bg-primary text-primary-foreground shadow-sm'
                  : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
              }`}
            >
              <Icon className="w-4 h-4 shrink-0" />
              <span>{section.label}</span>
              {section.id === 'alerts' && unreadAlerts.length > 0 && (
                <Badge variant="destructive" className="ml-auto text-xs px-1.5 py-0.5 min-w-[20px] h-5">
                  {unreadAlerts.length}
                </Badge>
              )}
            </button>
          );
        })}
      </nav>

      <div className="p-3 border-t border-border">
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          className="w-full justify-start gap-3"
        >
          {theme === 'dark' ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          <span>{theme === 'dark' ? 'Light Mode' : 'Dark Mode'}</span>
        </Button>
      </div>
    </div>
  );

  // Loading state
  if (familyLoading || !family) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <motion.div
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          className="flex flex-col items-center gap-4"
        >
          <div className="w-16 h-16 rounded-2xl bg-primary flex items-center justify-center">
            <Shield className="w-8 h-8 text-primary-foreground animate-pulse" />
          </div>
          <div className="text-center">
            <h2 className="font-bold text-lg">Family Monitor</h2>
            <p className="text-muted-foreground text-sm">Loading your dashboard...</p>
          </div>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex flex-col bg-background">
      <div className="flex flex-1">
        {/* Desktop Sidebar */}
        <aside className="hidden md:flex w-60 border-r border-border bg-card flex-col shrink-0">
          <SidebarContent />
        </aside>

        {/* Mobile Sidebar */}
        <Sheet open={sidebarOpen} onOpenChange={setSidebarOpen}>
          <SheetContent side="left" className="w-60 p-0">
            <SidebarContent />
          </SheetContent>
        </Sheet>

        {/* Main Content */}
        <main className="flex-1 flex flex-col min-w-0">
          {/* Top bar */}
          <header className="sticky top-0 z-40 bg-background/80 backdrop-blur-md border-b border-border">
            <div className="flex items-center gap-3 px-4 py-3">
              <Button
                variant="ghost"
                size="icon"
                className="md:hidden"
                onClick={() => setSidebarOpen(true)}
              >
                <Menu className="w-5 h-5" />
              </Button>
              <div className="flex-1">
                <h1 className="font-bold text-lg capitalize">
                  {SECTIONS.find(s => s.id === activeSection)?.label || 'Dashboard'}
                </h1>
                <p className="text-xs text-muted-foreground">{family.name}</p>
              </div>
              <div className="flex items-center gap-2">
                {unreadAlerts.length > 0 && (
                  <Badge variant="destructive" className="text-xs">
                    {unreadAlerts.length} unread
                  </Badge>
                )}
              </div>
            </div>
          </header>

          {/* Content Area */}
          <div className="flex-1 p-4 md:p-6 overflow-y-auto custom-scrollbar">
            <AnimatePresence mode="wait">
              <motion.div
                key={activeSection}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.2 }}
              >
                {activeSection === 'dashboard' && <DashboardSection />}
                {activeSection === 'family' && <FamilySection />}
                {activeSection === 'devices' && <DevicesSection />}
                {activeSection === 'screentime' && <ScreenTimeSection />}
                {activeSection === 'appusage' && <AppUsageSection />}
                {activeSection === 'location' && <LocationSection />}
                {activeSection === 'filters' && <FiltersSection />}
                {activeSection === 'alerts' && <AlertsSection />}
                {activeSection === 'schedules' && <SchedulesSection />}
              </motion.div>
            </AnimatePresence>
          </div>

          {/* Footer */}
          <footer className="border-t border-border bg-card px-4 py-3 text-center">
            <p className="text-xs text-muted-foreground">Family Monitor v1.0 &mdash; Keeping your family safe</p>
          </footer>
        </main>
      </div>
    </div>
  );

  // ==================== DASHBOARD SECTION ====================
  function DashboardSection() {
    return (
      <div className="space-y-6">
        {/* Summary Cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center">
                    <Users className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Members</p>
                    <p className="text-2xl font-bold">{allMembers.length}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-green-100 dark:bg-green-900/30 flex items-center justify-center">
                    <Wifi className="w-5 h-5 text-green-600 dark:text-green-400" />
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Online</p>
                    <p className="text-2xl font-bold text-green-600 dark:text-green-400">{onlineDevices.length}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-gray-100 dark:bg-gray-900/30 flex items-center justify-center">
                    <WifiOff className="w-5 h-5 text-gray-500 dark:text-gray-400" />
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Offline</p>
                    <p className="text-2xl font-bold">{offlineDevices.length}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}>
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
                    <AlertTriangle className="w-5 h-5 text-red-600 dark:text-red-400" />
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Alerts</p>
                    <p className="text-2xl font-bold text-red-600 dark:text-red-400">{unreadAlerts.length}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        </div>

        {/* Screen Time Chart + Quick Stats */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <Card className="lg:col-span-2">
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Weekly Screen Time</CardTitle>
              <CardDescription>Average daily usage across all devices</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={weeklyScreenTimeData} barGap={4}>
                    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                    <XAxis dataKey="day" className="text-xs" tick={{ fill: 'var(--muted-foreground)' }} />
                    <YAxis className="text-xs" tick={{ fill: 'var(--muted-foreground)' }} tickFormatter={(v) => `${v}m`} />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: 'var(--card)',
                        border: '1px solid var(--border)',
                        borderRadius: '8px',
                        color: 'var(--foreground)',
                      }}
                      formatter={(value: number) => [formatMinutes(value), '']}
                    />
                    <Bar dataKey="total" name="Usage" fill="#10b981" radius={[4, 4, 0, 0]} />
                    <Bar dataKey="limit" name="Limit" fill="#d1fae5" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Quick Stats</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-sm">
                  <Clock className="w-4 h-4 text-emerald-500" />
                  <span className="text-muted-foreground">Total Screen Time Today</span>
                </div>
                <p className="text-2xl font-bold pl-6">{formatMinutes(totalScreenTimeToday)}</p>
              </div>
              <Separator />
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-sm">
                  <BarChart3 className="w-4 h-4 text-amber-500" />
                  <span className="text-muted-foreground">Most Used App</span>
                </div>
                <p className="text-lg font-bold pl-6">{mostUsedApp ? `${mostUsedApp[0]} (${formatMinutes(mostUsedApp[1])})` : 'N/A'}</p>
              </div>
              <Separator />
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-sm">
                  <Battery className="w-4 h-4 text-blue-500" />
                  <span className="text-muted-foreground">Avg Battery Level</span>
                </div>
                <div className="pl-6 space-y-1">
                  <p className="text-lg font-bold">{avgBattery}%</p>
                  <Progress value={avgBattery} className="h-2" />
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Recent Alerts */}
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-base">Recent Alerts</CardTitle>
              <Button variant="ghost" size="sm" onClick={() => setActiveSection('alerts')}>
                View All <ChevronRight className="w-4 h-4 ml-1" />
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-2 max-h-64 overflow-y-auto custom-scrollbar">
              {allAlerts.slice(0, 5).map(alert => {
                const AlertIcon = getAlertIcon(alert.type);
                return (
                  <div key={alert.id} className="flex items-start gap-3 p-3 rounded-lg bg-muted/50 hover:bg-muted transition-colors">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${
                      alert.severity === 'critical' ? 'bg-red-100 dark:bg-red-900/30' :
                      alert.severity === 'warning' ? 'bg-yellow-100 dark:bg-yellow-900/30' :
                      'bg-blue-100 dark:bg-blue-900/30'
                    }`}>
                      <AlertIcon className={`w-4 h-4 ${
                        alert.severity === 'critical' ? 'text-red-600 dark:text-red-400' :
                        alert.severity === 'warning' ? 'text-yellow-600 dark:text-yellow-400' :
                        'text-blue-600 dark:text-blue-400'
                      }`} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-medium truncate">{alert.title}</p>
                        {!alert.read && <span className="w-2 h-2 rounded-full bg-primary shrink-0" />}
                      </div>
                      <p className="text-xs text-muted-foreground truncate">{alert.message}</p>
                    </div>
                    <span className="text-xs text-muted-foreground shrink-0">{formatDateTime(alert.createdAt)}</span>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // ==================== FAMILY SECTION ====================
  function FamilySection() {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold">Family Members</h2>
            <p className="text-sm text-muted-foreground">{allMembers.length} members in {family.name}</p>
          </div>
          <Dialog open={addMemberOpen} onOpenChange={setAddMemberOpen}>
            <DialogTrigger asChild>
              <Button size="sm"><Plus className="w-4 h-4 mr-2" /> Add Member</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Family Member</DialogTitle>
                <DialogDescription>Add a new member to your family group.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label>Name</Label>
                  <Input
                    value={newMember.name}
                    onChange={e => setNewMember(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="Enter name"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Email</Label>
                  <Input
                    value={newMember.email}
                    onChange={e => setNewMember(prev => ({ ...prev, email: e.target.value }))}
                    placeholder="Enter email (optional)"
                    type="email"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Role</Label>
                  <Select value={newMember.role} onValueChange={v => setNewMember(prev => ({ ...prev, role: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="parent">Parent</SelectItem>
                      <SelectItem value="child">Child</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Avatar</Label>
                  <div className="flex gap-2 flex-wrap">
                    {['👨', '👩', '👦', '👧', '🧒', '🧑', '👴', '👵', '👶'].map(emoji => (
                      <button
                        key={emoji}
                        onClick={() => setNewMember(prev => ({ ...prev, avatar: emoji }))}
                        className={`w-10 h-10 rounded-lg text-xl flex items-center justify-center transition-all ${
                          newMember.avatar === emoji ? 'bg-primary/20 ring-2 ring-primary' : 'bg-muted hover:bg-muted/80'
                        }`}
                      >
                        {emoji}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setAddMemberOpen(false)}>Cancel</Button>
                <Button onClick={() => addMemberMutation.mutate(newMember)} disabled={!newMember.name || addMemberMutation.isPending}>
                  {addMemberMutation.isPending ? 'Adding...' : 'Add Member'}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {allMembers.map(member => (
            <motion.div key={member.id} layout>
              <Card className="overflow-hidden">
                <CardContent className="p-0">
                  <button
                    className="w-full p-4 flex items-center gap-3 text-left hover:bg-muted/50 transition-colors"
                    onClick={() => setExpandedMember(expandedMember === member.id ? null : member.id)}
                  >
                    <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center text-2xl shrink-0">
                      {member.avatar || '🧑'}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="font-semibold truncate">{member.name}</p>
                        <Badge variant={member.role === 'parent' ? 'default' : 'secondary'} className="text-xs shrink-0">
                          {member.role === 'parent' ? 'Parent' : 'Child'}
                        </Badge>
                      </div>
                      {member.email && <p className="text-xs text-muted-foreground truncate">{member.email}</p>}
                      <p className="text-xs text-muted-foreground">{member.devices.length} device{member.devices.length !== 1 ? 's' : ''}</p>
                    </div>
                    {expandedMember === member.id ? <ChevronUp className="w-4 h-4 text-muted-foreground" /> : <ChevronDown className="w-4 h-4 text-muted-foreground" />}
                  </button>

                  <AnimatePresence>
                    {expandedMember === member.id && (
                      <motion.div
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: 'auto', opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        transition={{ duration: 0.2 }}
                        className="overflow-hidden"
                      >
                        <div className="px-4 pb-4 space-y-2">
                          <Separator />
                          <p className="text-xs font-medium text-muted-foreground pt-2">Devices</p>
                          {member.devices.length === 0 ? (
                            <p className="text-xs text-muted-foreground">No devices assigned</p>
                          ) : (
                            member.devices.map(device => {
                              const DeviceIcon = getDeviceIcon(device.type);
                              return (
                                <div key={device.id} className="flex items-center gap-3 p-2 rounded-lg bg-muted/50">
                                  <DeviceIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                                  <div className="flex-1 min-w-0">
                                    <p className="text-sm font-medium truncate">{device.name}</p>
                                    <p className="text-xs text-muted-foreground">{device.model || device.type}</p>
                                  </div>
                                  <div className="flex items-center gap-2">
                                    {device.batteryLevel !== null && (
                                      <span className="text-xs text-muted-foreground">{device.batteryLevel}%</span>
                                    )}
                                    <Badge variant={device.status === 'online' ? 'default' : 'secondary'} className="text-xs">
                                      {device.status}
                                    </Badge>
                                  </div>
                                </div>
                              );
                            })
                          )}
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    );
  }

  // ==================== DEVICES SECTION ====================
  function DevicesSection() {
    const selectedDeviceData = selectedDevice ? allDevices.find(d => d.id === selectedDevice) : null;

    if (selectedDeviceData) {
      return <DeviceDetail device={selectedDeviceData} onBack={() => setSelectedDevice(null)} />;
    }

    return (
      <div className="space-y-6">
        <div>
          <h2 className="text-xl font-bold">Devices</h2>
          <p className="text-sm text-muted-foreground">{allDevices.length} devices registered &middot; {onlineDevices.length} online</p>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {allDevices.map((device, index) => {
            const DeviceIcon = getDeviceIcon(device.type);
            const member = allMembers.find(m => m.id === device.memberId);
            return (
              <motion.div
                key={device.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <Card
                  className="cursor-pointer hover:shadow-md transition-all hover:border-primary/50"
                  onClick={() => setSelectedDevice(device.id)}
                >
                  <CardContent className="p-4">
                    <div className="flex items-start gap-3">
                      <div className={`w-12 h-12 rounded-xl flex items-center justify-center shrink-0 ${
                        device.status === 'online' ? 'bg-emerald-100 dark:bg-emerald-900/30' : 'bg-gray-100 dark:bg-gray-900/30'
                      }`}>
                        <DeviceIcon className={`w-6 h-6 ${
                          device.status === 'online' ? 'text-emerald-600 dark:text-emerald-400' : 'text-gray-500'
                        }`} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold truncate">{device.name}</p>
                        <p className="text-xs text-muted-foreground">{device.os || device.type} &middot; {device.model || ''}</p>
                        {member && <p className="text-xs text-muted-foreground">{member.avatar} {member.name}</p>}
                      </div>
                    </div>
                    <div className="mt-3 flex items-center gap-3">
                      <Badge variant={device.status === 'online' ? 'default' : 'secondary'} className="text-xs">
                        {device.status === 'online' ? <Wifi className="w-3 h-3 mr-1" /> : <WifiOff className="w-3 h-3 mr-1" />}
                        {device.status}
                      </Badge>
                      {device.batteryLevel !== null && (
                        <div className="flex items-center gap-1.5 flex-1">
                          <Battery className={`w-3.5 h-3.5 ${
                            device.batteryLevel > 50 ? 'text-green-500' : device.batteryLevel > 20 ? 'text-yellow-500' : 'text-red-500'
                          }`} />
                          <Progress value={device.batteryLevel} className="h-1.5 flex-1" />
                          <span className="text-xs text-muted-foreground">{device.batteryLevel}%</span>
                        </div>
                      )}
                    </div>
                    {device.lastSeen && (
                      <p className="text-xs text-muted-foreground mt-2">Last seen: {formatDateTime(device.lastSeen)}</p>
                    )}
                  </CardContent>
                </Card>
              </motion.div>
            );
          })}
        </div>
      </div>
    );
  }

  function DeviceDetail({ device, onBack }: { device: DeviceData; onBack: () => void }) {
    const member = allMembers.find(m => m.id === device.memberId);

    // Screen time history chart
    const screenTimeChart = device.screenTime
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
      .map(st => ({
        day: formatDate(st.date),
        usage: st.totalMinutes,
        limit: st.limitMinutes || 0,
      }));

    // App usage breakdown
    const appBreakdown = (() => {
      const apps = new Map<string, { total: number; category: string }>();
      device.appUsage.forEach(au => {
        const existing = apps.get(au.appName);
        if (existing) {
          existing.total += au.usageMinutes;
        } else {
          apps.set(au.appName, { total: au.usageMinutes, category: au.category || 'other' });
        }
      });
      return Array.from(apps.entries())
        .map(([name, data]) => ({ name, total: data.total, category: data.category }))
        .sort((a, b) => b.total - a.total)
        .slice(0, 8);
    })();

    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={onBack}>
            <ChevronRight className="w-5 h-5 rotate-180" />
          </Button>
          <div>
            <h2 className="text-xl font-bold">{device.name}</h2>
            <p className="text-sm text-muted-foreground">
              {device.os} &middot; {device.model} &middot; {member?.avatar} {member?.name}
            </p>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <Badge variant={device.status === 'online' ? 'default' : 'secondary'}>
              {device.status}
            </Badge>
            <Button
              variant="outline"
              size="sm"
              onClick={() => updateDeviceMutation.mutate({
                id: device.id,
                status: device.status === 'online' ? 'offline' : 'online',
              })}
            >
              {device.status === 'online' ? 'Set Offline' : 'Set Online'}
            </Button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Screen Time History */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Screen Time History</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-48">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={screenTimeChart} barGap={2}>
                    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                    <XAxis dataKey="day" className="text-xs" tick={{ fill: 'var(--muted-foreground)' }} />
                    <YAxis tick={{ fill: 'var(--muted-foreground)' }} tickFormatter={v => `${v}m`} />
                    <Tooltip
                      contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px', color: 'var(--foreground)' }}
                      formatter={(value: number) => [formatMinutes(value), '']}
                    />
                    <Bar dataKey="usage" name="Usage" fill="#10b981" radius={[4, 4, 0, 0]} />
                    <Bar dataKey="limit" name="Limit" fill="#d1fae5" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>

          {/* App Usage Breakdown */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">App Usage</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-48">
                {appBreakdown.length > 0 ? (
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={appBreakdown}
                        dataKey="total"
                        nameKey="name"
                        cx="50%"
                        cy="50%"
                        innerRadius={40}
                        outerRadius={70}
                        paddingAngle={2}
                      >
                        {appBreakdown.map((_, index) => (
                          <Cell key={`cell-${index}`} fill={CHART_COLORS[index % CHART_COLORS.length]} />
                        ))}
                      </Pie>
                      <Tooltip
                        contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px', color: 'var(--foreground)' }}
                        formatter={(value: number) => [formatMinutes(value), '']}
                      />
                    </PieChart>
                  </ResponsiveContainer>
                ) : (
                  <div className="h-full flex items-center justify-center text-muted-foreground text-sm">No app usage data</div>
                )}
              </div>
              <div className="mt-2 space-y-1 max-h-32 overflow-y-auto custom-scrollbar">
                {appBreakdown.map((app, i) => (
                  <div key={app.name} className="flex items-center gap-2 text-xs">
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: CHART_COLORS[i % CHART_COLORS.length] }} />
                    <span className="flex-1 truncate">{app.name}</span>
                    <span className="text-muted-foreground">{formatMinutes(app.total)}</span>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Recent Locations */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Recent Locations</CardTitle>
          </CardHeader>
          <CardContent>
            {device.location.length === 0 ? (
              <p className="text-sm text-muted-foreground">No location data available</p>
            ) : (
              <div className="space-y-2 max-h-48 overflow-y-auto custom-scrollbar">
                {device.location.map(loc => (
                  <div key={loc.id} className="flex items-center gap-3 p-2 rounded-lg bg-muted/50">
                    <MapPin className="w-4 h-4 text-emerald-500 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm truncate">{loc.address || `${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}`}</p>
                      <p className="text-xs text-muted-foreground">{formatDateTime(loc.timestamp)}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  // ==================== SCREEN TIME SECTION ====================
  function ScreenTimeSection() {
    const [limitDeviceId, setLimitDeviceId] = useState('');
    const [limitMinutes, setLimitMinutes] = useState(120);

    // Per-device screen time for today
    const deviceScreenTime = allDevices.map(device => {
      const todayST = device.screenTime.find(st => {
        const stDate = new Date(st.date);
        stDate.setHours(0, 0, 0, 0);
        return stDate.getTime() === today.getTime();
      });
      return {
        deviceName: device.name,
        deviceId: device.id,
        usage: todayST?.totalMinutes || 0,
        limit: todayST?.limitMinutes || 120,
      };
    });

    return (
      <div className="space-y-6">
        <div>
          <h2 className="text-xl font-bold">Screen Time</h2>
          <p className="text-sm text-muted-foreground">Monitor and manage daily screen time limits</p>
        </div>

        {/* Weekly Chart */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Weekly Overview</CardTitle>
            <CardDescription>Average screen time across all devices</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={weeklyScreenTimeData} barGap={4}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                  <XAxis dataKey="day" tick={{ fill: 'var(--muted-foreground)' }} />
                  <YAxis tick={{ fill: 'var(--muted-foreground)' }} tickFormatter={v => `${v}m`} />
                  <Tooltip
                    contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px', color: 'var(--foreground)' }}
                    formatter={(value: number) => [formatMinutes(value), '']}
                  />
                  <Legend />
                  <Bar dataKey="total" name="Usage" fill="#10b981" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="limit" name="Limit" fill="#d1fae5" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Today's Usage vs Limit */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Today&apos;s Usage vs Limit</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {deviceScreenTime.map(item => {
                const pct = Math.min((item.usage / item.limit) * 100, 100);
                const exceeded = item.usage > item.limit;
                return (
                  <div key={item.deviceId} className="space-y-1.5">
                    <div className="flex items-center justify-between text-sm">
                      <span className="font-medium">{item.deviceName}</span>
                      <span className={exceeded ? 'text-red-500 font-semibold' : 'text-muted-foreground'}>
                        {formatMinutes(item.usage)} / {formatMinutes(item.limit)}
                      </span>
                    </div>
                    <Progress value={pct} className={`h-2 ${exceeded ? '[&>div]:bg-red-500' : ''}`} />
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* Set Daily Limit */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Set Daily Limit</CardTitle>
            <CardDescription>Set screen time limits for each device</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col sm:flex-row gap-3">
              <Select value={limitDeviceId} onValueChange={setLimitDeviceId}>
                <SelectTrigger className="flex-1">
                  <SelectValue placeholder="Select device" />
                </SelectTrigger>
                <SelectContent>
                  {allDevices.map(d => (
                    <SelectItem key={d.id} value={d.id}>{d.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <div className="flex items-center gap-2">
                <Input
                  type="number"
                  value={limitMinutes}
                  onChange={e => setLimitMinutes(parseInt(e.target.value) || 0)}
                  className="w-24"
                  min={0}
                  max={720}
                />
                <span className="text-sm text-muted-foreground">minutes</span>
              </div>
              <Button
                onClick={() => {
                  if (limitDeviceId) {
                    setScreenTimeLimitMutation.mutate({ deviceId: limitDeviceId, limitMinutes });
                  }
                }}
                disabled={!limitDeviceId || setScreenTimeLimitMutation.isPending}
              >
                Set Limit
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // ==================== APP USAGE SECTION ====================
  function AppUsageSection() {
    // Per-member app usage
    const memberAppUsage = childMembers.map(member => {
      const memberDevices = member.devices;
      const deviceIds = new Set(memberDevices.map(d => d.id));
      const memberApps = new Map<string, number>();
      (appUsageData || []).forEach(au => {
        if (deviceIds.has(au.deviceId)) {
          memberApps.set(au.appName, (memberApps.get(au.appName) || 0) + au.usageMinutes);
        }
      });
      const sorted = Array.from(memberApps.entries())
        .map(([name, total]) => ({ name, total }))
        .sort((a, b) => b.total - a.total)
        .slice(0, 5);
      return { member, apps: sorted };
    });

    return (
      <div className="space-y-6">
        <div>
          <h2 className="text-xl font-bold">App Usage</h2>
          <p className="text-sm text-muted-foreground">Track which apps your children use most</p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Top Apps Pie Chart */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Top Apps by Usage</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={topAppsData}
                      dataKey="value"
                      nameKey="name"
                      cx="50%"
                      cy="50%"
                      innerRadius={50}
                      outerRadius={90}
                      paddingAngle={2}
                      label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    >
                      {topAppsData.map((_, index) => (
                        <Cell key={`cell-${index}`} fill={CHART_COLORS[index % CHART_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px', color: 'var(--foreground)' }}
                      formatter={(value: number) => [formatMinutes(value), '']}
                    />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>

          {/* Category Breakdown */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Category Breakdown</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="h-64">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={categoryBreakdown} layout="vertical">
                    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                    <XAxis type="number" tick={{ fill: 'var(--muted-foreground)' }} tickFormatter={v => formatMinutes(v)} />
                    <YAxis type="category" dataKey="name" tick={{ fill: 'var(--muted-foreground)' }} width={90} />
                    <Tooltip
                      contentStyle={{ backgroundColor: 'var(--card)', border: '1px solid var(--border)', borderRadius: '8px', color: 'var(--foreground)' }}
                      formatter={(value: number) => [formatMinutes(value), '']}
                    />
                    <Bar dataKey="value" radius={[0, 4, 4, 0]}>
                      {categoryBreakdown.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={CATEGORY_COLORS[entry.name] || CHART_COLORS[index % CHART_COLORS.length]} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Per-member App Usage */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {memberAppUsage.map(({ member, apps }) => (
            <Card key={member.id}>
              <CardHeader className="pb-2">
                <div className="flex items-center gap-2">
                  <span className="text-xl">{member.avatar}</span>
                  <CardTitle className="text-base">{member.name}&apos;s Apps</CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                {apps.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No app usage data</p>
                ) : (
                  <div className="space-y-2">
                    {apps.map((app, i) => {
                      const CatIcon = getCategoryIcon(
                        (appUsageData || []).find(au => au.appName === app.name)?.category || 'other'
                      );
                      return (
                        <div key={app.name} className="flex items-center gap-2">
                          <CatIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                          <span className="text-sm flex-1 truncate">{app.name}</span>
                          <span className="text-sm font-medium">{formatMinutes(app.total)}</span>
                        </div>
                      );
                    })}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    );
  }

  // ==================== LOCATION SECTION ====================
  function LocationSection() {
    return (
      <div className="space-y-6">
        <div>
          <h2 className="text-xl font-bold">Location History</h2>
          <p className="text-sm text-muted-foreground">Track device locations and geofence alerts</p>
        </div>

        {/* Geofence Alerts */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <MapPinned className="w-4 h-4 text-amber-500" />
              Geofence Alerts
            </CardTitle>
          </CardHeader>
          <CardContent>
            {geofenceAlerts.length === 0 ? (
              <p className="text-sm text-muted-foreground">No geofence alerts</p>
            ) : (
              <div className="space-y-2 max-h-48 overflow-y-auto custom-scrollbar">
                {geofenceAlerts.map(alert => (
                  <div key={alert.id} className="flex items-center gap-3 p-3 rounded-lg bg-muted/50">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${
                      alert.severity === 'critical' ? 'bg-red-100 dark:bg-red-900/30' : 'bg-yellow-100 dark:bg-yellow-900/30'
                    }`}>
                      <MapPinned className={`w-4 h-4 ${
                        alert.severity === 'critical' ? 'text-red-500' : 'text-yellow-500'
                      }`} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">{alert.title}</p>
                      <p className="text-xs text-muted-foreground">{alert.message}</p>
                    </div>
                    <Badge className={`text-xs ${SEVERITY_COLORS[alert.severity]}`}>
                      {alert.severity}
                    </Badge>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Location History */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Recent Locations</CardTitle>
          </CardHeader>
          <CardContent>
            {(locationData || []).length === 0 ? (
              <p className="text-sm text-muted-foreground">No location data available</p>
            ) : (
              <div className="space-y-2 max-h-96 overflow-y-auto custom-scrollbar">
                {(locationData || []).map(loc => (
                  <div key={loc.id} className="flex items-center gap-3 p-3 rounded-lg bg-muted/50 hover:bg-muted transition-colors">
                    <div className="w-8 h-8 rounded-lg bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center shrink-0">
                      <MapPin className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{loc.address || `${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}`}</p>
                      <div className="flex items-center gap-2 text-xs text-muted-foreground">
                        {loc.device?.member?.name && <span>{loc.device.member.name}</span>}
                        {loc.device?.name && <span>&middot; {loc.device.name}</span>}
                      </div>
                    </div>
                    <span className="text-xs text-muted-foreground shrink-0">{formatDateTime(loc.timestamp)}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  // ==================== FILTERS SECTION ====================
  function FiltersSection() {
    const categories = ['violence', 'adult', 'gambling', 'social', 'games'];
    const categoryIcons: Record<string, React.ElementType> = {
      violence: ShieldAlert,
      adult: EyeOff,
      gambling: AlertCircle,
      social: MessageCircle,
      games: Gamepad2,
    };

    // Group filters by device
    const filtersByDevice = new Map<string, ContentFilterData[]>();
    filteredContentFilters.forEach(f => {
      const key = f.deviceId || 'global';
      if (!filtersByDevice.has(key)) filtersByDevice.set(key, []);
      filtersByDevice.get(key)!.push(f);
    });

    return (
      <div className="space-y-6">
        <div>
          <h2 className="text-xl font-bold">Content Filtering</h2>
          <p className="text-sm text-muted-foreground">Manage content filters and block levels</p>
        </div>

        {/* Device Filter */}
        <div className="flex items-center gap-3">
          <Label className="text-sm">Filter by device:</Label>
          <Select value={filterDevice} onValueChange={setFilterDevice}>
            <SelectTrigger className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Devices</SelectItem>
              {allDevices.map(d => (
                <SelectItem key={d.id} value={d.id}>{d.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {/* Filter Cards per Device */}
        {Array.from(filtersByDevice.entries()).map(([deviceId, filters]) => {
          const device = allDevices.find(d => d.id === deviceId);
          const member = device ? allMembers.find(m => m.id === device.memberId) : null;

          return (
            <Card key={deviceId}>
              <CardHeader className="pb-2">
                <div className="flex items-center gap-2">
                  {member && <span className="text-lg">{member.avatar}</span>}
                  <CardTitle className="text-base">
                    {device?.name || 'Global'} {member && `(${member.name})`}
                  </CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {categories.map(cat => {
                    const filter = filters.find(f => f.category === cat);
                    const CatIcon = categoryIcons[cat] || Shield;

                    return (
                      <div key={cat} className="flex items-center gap-4">
                        <div className="flex items-center gap-2 w-32">
                          <CatIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                          <span className="text-sm font-medium capitalize">{cat}</span>
                        </div>
                        <Switch
                          checked={filter?.enabled ?? true}
                          onCheckedChange={(checked) => {
                            if (filter) {
                              updateFilterMutation.mutate({ id: filter.id, enabled: checked });
                            }
                          }}
                        />
                        <Select
                          value={filter?.blockLevel || 'medium'}
                          onValueChange={(value) => {
                            if (filter) {
                              updateFilterMutation.mutate({ id: filter.id, blockLevel: value });
                            }
                          }}
                        >
                          <SelectTrigger className="w-32">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="low">Low</SelectItem>
                            <SelectItem value="medium">Medium</SelectItem>
                            <SelectItem value="high">High</SelectItem>
                          </SelectContent>
                        </Select>
                        <Badge variant={filter?.enabled ? 'default' : 'secondary'} className="text-xs">
                          {filter?.enabled ? 'Active' : 'Disabled'}
                        </Badge>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    );
  }

  // ==================== ALERTS SECTION ====================
  function AlertsSection() {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h2 className="text-xl font-bold">Alerts</h2>
            <p className="text-sm text-muted-foreground">{allAlerts.length} total &middot; {unreadAlerts.length} unread</p>
          </div>
          <div className="flex items-center gap-2">
            <Label className="text-sm">Filter:</Label>
            <Select value={alertFilter} onValueChange={setAlertFilter}>
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                <SelectItem value="critical">Critical</SelectItem>
                <SelectItem value="warning">Warning</SelectItem>
                <SelectItem value="info">Info</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <div className="space-y-3">
          {filteredAlerts.length === 0 ? (
            <Card>
              <CardContent className="p-8 text-center">
                <CheckCircle className="w-12 h-12 text-emerald-500 mx-auto mb-3" />
                <p className="font-medium">No alerts found</p>
                <p className="text-sm text-muted-foreground">Your family is safe!</p>
              </CardContent>
            </Card>
          ) : (
            filteredAlerts.map((alert, index) => {
              const AlertIcon = getAlertIcon(alert.type);
              return (
                <motion.div
                  key={alert.id}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.03 }}
                >
                  <Card className={`transition-all ${!alert.read ? 'border-l-4 border-l-primary' : ''}`}>
                    <CardContent className="p-4">
                      <div className="flex items-start gap-3">
                        <div className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0 ${
                          alert.severity === 'critical' ? 'bg-red-100 dark:bg-red-900/30' :
                          alert.severity === 'warning' ? 'bg-yellow-100 dark:bg-yellow-900/30' :
                          'bg-blue-100 dark:bg-blue-900/30'
                        }`}>
                          <AlertIcon className={`w-5 h-5 ${
                            alert.severity === 'critical' ? 'text-red-600 dark:text-red-400' :
                            alert.severity === 'warning' ? 'text-yellow-600 dark:text-yellow-400' :
                            'text-blue-600 dark:text-blue-400'
                          }`} />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <p className="font-semibold">{alert.title}</p>
                            <Badge className={`text-xs ${SEVERITY_COLORS[alert.severity]}`}>
                              {alert.severity}
                            </Badge>
                            <Badge variant="outline" className="text-xs capitalize">
                              {alert.type.replace('_', ' ')}
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground mt-1">{alert.message}</p>
                          <div className="flex items-center gap-3 mt-2 text-xs text-muted-foreground">
                            {alert.member && <span>{alert.member.avatar} {alert.member.name}</span>}
                            {alert.device && <span>&middot; {alert.device.name}</span>}
                            <span>&middot; {formatDateTime(alert.createdAt)}</span>
                          </div>
                        </div>
                        {!alert.read && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => markAlertMutation.mutate(alert.id)}
                          >
                            <Eye className="w-4 h-4 mr-1" /> Mark Read
                          </Button>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </motion.div>
              );
            })
          )}
        </div>
      </div>
    );
  }

  // ==================== SCHEDULES SECTION ====================
  function SchedulesSection() {
    // Today's schedule timeline
    const todayDay = new Date().getDay(); // 0=Sun, 1=Mon...
    const todayDayNum = todayDay === 0 ? 7 : todayDay; // Convert to 1=Mon, 7=Sun

    const todaySchedules = (scheduleData || []).filter(s => {
      if (!s.enabled) return false;
      const days = s.daysOfWeek.split(',').map(Number);
      return days.includes(todayDayNum);
    });

    const scheduleTypeColors: Record<string, string> = {
      bedtime: 'bg-indigo-500',
      study_time: 'bg-amber-500',
      free_time: 'bg-emerald-500',
    };

    const scheduleTypeLabels: Record<string, string> = {
      bedtime: 'Bedtime',
      study_time: 'Study Time',
      free_time: 'Free Time',
    };

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold">Schedules</h2>
            <p className="text-sm text-muted-foreground">Manage bedtime, study time, and free time rules</p>
          </div>
          <Dialog open={addScheduleOpen} onOpenChange={setAddScheduleOpen}>
            <DialogTrigger asChild>
              <Button size="sm"><Plus className="w-4 h-4 mr-2" /> Add Schedule</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create Schedule Rule</DialogTitle>
                <DialogDescription>Set up a new schedule for device usage.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label>Name</Label>
                  <Input
                    value={newSchedule.name}
                    onChange={e => setNewSchedule(prev => ({ ...prev, name: e.target.value }))}
                    placeholder="e.g., Bedtime"
                  />
                </div>
                <div className="space-y-2">
                  <Label>Type</Label>
                  <Select value={newSchedule.type} onValueChange={v => setNewSchedule(prev => ({ ...prev, type: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="bedtime">Bedtime</SelectItem>
                      <SelectItem value="study_time">Study Time</SelectItem>
                      <SelectItem value="free_time">Free Time</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-2">
                    <Label>Start Hour</Label>
                    <Input type="number" min={0} max={23} value={newSchedule.startHour} onChange={e => setNewSchedule(prev => ({ ...prev, startHour: parseInt(e.target.value) || 0 }))} />
                  </div>
                  <div className="space-y-2">
                    <Label>Start Minute</Label>
                    <Input type="number" min={0} max={59} value={newSchedule.startMinute} onChange={e => setNewSchedule(prev => ({ ...prev, startMinute: parseInt(e.target.value) || 0 }))} />
                  </div>
                  <div className="space-y-2">
                    <Label>End Hour</Label>
                    <Input type="number" min={0} max={23} value={newSchedule.endHour} onChange={e => setNewSchedule(prev => ({ ...prev, endHour: parseInt(e.target.value) || 0 }))} />
                  </div>
                  <div className="space-y-2">
                    <Label>End Minute</Label>
                    <Input type="number" min={0} max={59} value={newSchedule.endMinute} onChange={e => setNewSchedule(prev => ({ ...prev, endMinute: parseInt(e.target.value) || 0 }))} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Device</Label>
                  <Select value={newSchedule.deviceId} onValueChange={v => setNewSchedule(prev => ({ ...prev, deviceId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Select device" /></SelectTrigger>
                    <SelectContent>
                      {allDevices.map(d => (
                        <SelectItem key={d.id} value={d.id}>{d.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Allowed Apps (comma-separated)</Label>
                  <Input
                    value={newSchedule.allowApps}
                    onChange={e => setNewSchedule(prev => ({ ...prev, allowApps: e.target.value }))}
                    placeholder="e.g., Khan Academy, Duolingo"
                  />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setAddScheduleOpen(false)}>Cancel</Button>
                <Button onClick={() => addScheduleMutation.mutate(newSchedule)} disabled={!newSchedule.name || addScheduleMutation.isPending}>
                  {addScheduleMutation.isPending ? 'Creating...' : 'Create'}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>

        {/* Today's Timeline */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Today&apos;s Schedule</CardTitle>
            <CardDescription>{DAY_NAMES[todayDayNum]}</CardDescription>
          </CardHeader>
          <CardContent>
            {todaySchedules.length === 0 ? (
              <p className="text-sm text-muted-foreground">No schedules active today</p>
            ) : (
              <div className="relative">
                {/* Hour markers */}
                <div className="flex justify-between text-xs text-muted-foreground mb-2">
                  {Array.from({ length: 7 }, (_, i) => (
                    <span key={i}>{(i * 4).toString().padStart(2, '0')}:00</span>
                  ))}
                </div>
                <div className="h-12 bg-muted rounded-lg relative overflow-hidden">
                  {todaySchedules.map((schedule, i) => {
                    const startPos = ((schedule.startHour + schedule.startMinute / 60) / 24) * 100;
                    const endPos = ((schedule.endHour + schedule.endMinute / 60) / 24) * 100;
                    const width = endPos > startPos ? endPos - startPos : (100 - startPos) + endPos;
                    return (
                      <div
                        key={schedule.id}
                        className={`absolute top-1 bottom-1 rounded-md ${scheduleTypeColors[schedule.type] || 'bg-gray-500'} opacity-70`}
                        style={{
                          left: `${startPos}%`,
                          width: `${Math.min(width, 100 - startPos)}%`,
                        }}
                        title={`${schedule.name}: ${formatTime(schedule.startHour, schedule.startMinute)} - ${formatTime(schedule.endHour, schedule.endMinute)}`}
                      />
                    );
                  })}
                </div>
                <div className="flex gap-3 mt-3 flex-wrap">
                  {Object.entries(scheduleTypeLabels).map(([type, label]) => (
                    <div key={type} className="flex items-center gap-1.5 text-xs">
                      <span className={`w-3 h-3 rounded-sm ${scheduleTypeColors[type]}`} />
                      <span>{label}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Schedule Rules List */}
        <div className="space-y-3">
          {(scheduleData || []).map((schedule, index) => {
            const member = schedule.device?.member;
            const days = schedule.daysOfWeek.split(',').map(Number);

            return (
              <motion.div
                key={schedule.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <Card className={!schedule.enabled ? 'opacity-60' : ''}>
                  <CardContent className="p-4">
                    <div className="flex items-center gap-3">
                      <div className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0 ${
                        schedule.type === 'bedtime' ? 'bg-indigo-100 dark:bg-indigo-900/30' :
                        schedule.type === 'study_time' ? 'bg-amber-100 dark:bg-amber-900/30' :
                        'bg-emerald-100 dark:bg-emerald-900/30'
                      }`}>
                        {schedule.type === 'bedtime' ? <Moon className="w-5 h-5 text-indigo-600 dark:text-indigo-400" /> :
                         schedule.type === 'study_time' ? <GraduationCap className="w-5 h-5 text-amber-600 dark:text-amber-400" /> :
                         <Sun className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="font-semibold">{schedule.name}</p>
                          <Badge variant="outline" className="text-xs capitalize">
                            {schedule.type.replace('_', ' ')}
                          </Badge>
                        </div>
                        <p className="text-sm text-muted-foreground">
                          {formatTime(schedule.startHour, schedule.startMinute)} - {formatTime(schedule.endHour, schedule.endMinute)}
                        </p>
                        <div className="flex items-center gap-1 mt-1">
                          {days.map(d => (
                            <span key={d} className={`text-xs px-1.5 py-0.5 rounded ${
                              d === todayDayNum ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'
                            }`}>
                              {DAY_NAMES[d]}
                            </span>
                          ))}
                        </div>
                        {schedule.device && (
                          <p className="text-xs text-muted-foreground mt-1">
                            {member?.avatar} {member?.name} &middot; {schedule.device.name}
                          </p>
                        )}
                        {schedule.allowApps && (
                          <p className="text-xs text-muted-foreground mt-0.5">
                            Allowed: {schedule.allowApps}
                          </p>
                        )}
                      </div>
                      <Switch
                        checked={schedule.enabled}
                        onCheckedChange={(checked) => toggleScheduleMutation.mutate({ id: schedule.id, enabled: checked })}
                      />
                    </div>
                  </CardContent>
                </Card>
              </motion.div>
            );
          })}
        </div>
      </div>
    );
  }
}
