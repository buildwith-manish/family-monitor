import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const devices = await db.device.findMany({
      include: {
        member: true,
        screenTime: { orderBy: { date: 'desc' }, take: 7 },
        appUsage: { orderBy: { date: 'desc' }, take: 30 },
        location: { orderBy: { timestamp: 'desc' }, take: 5 },
      },
      orderBy: { name: 'asc' },
    });

    return NextResponse.json(devices);
  } catch (error) {
    console.error('Devices GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch devices' }, { status: 500 });
  }
}
