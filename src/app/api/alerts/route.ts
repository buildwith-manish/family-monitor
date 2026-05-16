import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const alerts = await db.alert.findMany({
      orderBy: { createdAt: 'desc' },
    });

    // Manually resolve member and device info
    const memberIds = [...new Set(alerts.map(a => a.memberId).filter(Boolean))] as string[];
    const deviceIds = [...new Set(alerts.map(a => a.deviceId).filter(Boolean))] as string[];

    const members = await db.member.findMany({
      where: { id: { in: memberIds } },
      select: { id: true, name: true, avatar: true },
    });

    const devices = await db.device.findMany({
      where: { id: { in: deviceIds } },
      select: { id: true, name: true },
    });

    const memberMap = new Map(members.map(m => [m.id, m]));
    const deviceMap = new Map(devices.map(d => [d.id, d]));

    const alertsWithRelations = alerts.map(alert => ({
      ...alert,
      member: alert.memberId ? memberMap.get(alert.memberId) || null : null,
      device: alert.deviceId ? deviceMap.get(alert.deviceId) || null : null,
    }));

    return NextResponse.json(alertsWithRelations);
  } catch (error) {
    console.error('Alerts GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch alerts' }, { status: 500 });
  }
}
