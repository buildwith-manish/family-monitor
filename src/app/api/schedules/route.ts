import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const schedules = await db.scheduleRule.findMany({
      orderBy: [{ type: 'asc' }, { startHour: 'asc' }],
    });

    // Manually resolve device info
    const deviceIds = [...new Set(schedules.map(s => s.deviceId).filter(Boolean))] as string[];

    const devices = await db.device.findMany({
      where: { id: { in: deviceIds } },
      select: { id: true, name: true, memberId: true },
    });

    const deviceMap = new Map(devices.map(d => [d.id, d]));

    // Also get member info for devices
    const memberIds = [...new Set(devices.map(d => d.memberId).filter(Boolean))];
    const members = await db.member.findMany({
      where: { id: { in: memberIds } },
      select: { id: true, name: true, avatar: true },
    });
    const memberMap = new Map(members.map(m => [m.id, m]));

    const schedulesWithRelations = schedules.map(schedule => ({
      ...schedule,
      device: schedule.deviceId ? (() => {
        const device = deviceMap.get(schedule.deviceId);
        if (!device) return null;
        const member = memberMap.get(device.memberId);
        return {
          name: device.name,
          member: member ? { name: member.name, avatar: member.avatar } : null,
        };
      })() : null,
    }));

    return NextResponse.json(schedulesWithRelations);
  } catch (error) {
    console.error('Schedules GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch schedules' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { name, type, startHour, startMinute, endHour, endMinute, daysOfWeek, allowApps, deviceId, enabled } = body;

    if (!name || !type || startHour === undefined || endHour === undefined) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    const schedule = await db.scheduleRule.create({
      data: {
        name,
        type,
        startHour,
        startMinute: startMinute || 0,
        endHour,
        endMinute: endMinute || 0,
        daysOfWeek: daysOfWeek || '1,2,3,4,5',
        allowApps: allowApps || '',
        deviceId: deviceId || null,
        enabled: enabled !== undefined ? enabled : true,
      },
    });

    return NextResponse.json(schedule);
  } catch (error) {
    console.error('Schedule POST error:', error);
    return NextResponse.json({ error: 'Failed to create schedule rule' }, { status: 500 });
  }
}
