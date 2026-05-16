import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { status, batteryLevel } = body;

    const device = await db.device.update({
      where: { id },
      data: {
        ...(status !== undefined && { status }),
        ...(batteryLevel !== undefined && { batteryLevel }),
        lastSeen: new Date(),
      },
    });

    return NextResponse.json(device);
  } catch (error) {
    console.error('Device PATCH error:', error);
    return NextResponse.json({ error: 'Failed to update device' }, { status: 500 });
  }
}
